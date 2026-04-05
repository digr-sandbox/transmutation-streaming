// Copyright (c) 2009-2010 Satoshi Nakamoto
// Copyright (c) 2009-present The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include <bitcoin-build-config.h> // IWYU pragma: keep

#include <net.h>

#include <addrdb.h>
#include <addrman.h>
#include <banman.h>
#include <clientversion.h>
#include <common/args.h>
#include <common/netif.h>
#include <compat/compat.h>
#include <consensus/consensus.h>
#include <crypto/sha256.h>
#include <i2p.h>
#include <key.h>
#include <logging.h>
#include <memusage.h>
#include <net_permissions.h>
#include <netaddress.h>
#include <netbase.h>
#include <node/eviction.h>
#include <node/interface_ui.h>
#include <protocol.h>
#include <random.h>
#include <scheduler.h>
#include <util/fs.h>
#include <util/sock.h>
#include <util/strencodings.h>
#include <util/thread.h>
#include <util/threadinterrupt.h>
#include <util/trace.h>
#include <util/translation.h>
#include <util/vector.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <functional>
#include <optional>
#include <string_view>
#include <unordered_map>

TRACEPOINT_SEMAPHORE(net, closed_connection);
TRACEPOINT_SEMAPHORE(net, evicted_inbound_connection);
TRACEPOINT_SEMAPHORE(net, inbound_connection);
TRACEPOINT_SEMAPHORE(net, outbound_connection);
TRACEPOINT_SEMAPHORE(net, outbound_message);

/** Maximum number of block-relay-only anchor connections */
static constexpr size_t MAX_BLOCK_RELAY_ONLY_ANCHORS = 2;
static_assert (MAX_BLOCK_RELAY_ONLY_ANCHORS <= static_cast<size_t>(MAX_BLOCK_RELAY_ONLY_CONNECTIONS), "MAX_BLOCK_RELAY_ONLY_ANCHORS must not exceed MAX_BLOCK_RELAY_ONLY_CONNECTIONS.");
/** Anchor IP address database file name */
const char* const ANCHORS_DATABASE_FILENAME = "anchors.dat";

// How often to dump addresses to peers.dat
static constexpr std::chrono::minutes DUMP_PEERS_INTERVAL{15};

/** Number of DNS seeds to query when the number of connections is low. */
static constexpr int DNSSEEDS_TO_QUERY_AT_ONCE = 3;

/** Minimum number of outbound connections under which we will keep fetching our address seeds. */
static constexpr int SEED_OUTBOUND_CONNECTION_THRESHOLD = 2;

/** How long to delay before querying DNS seeds
 *
 * If we have more than THRESHOLD entries in addrman, then it's likely
 * that we got those addresses from having previously connected to the P2P
 * network, and that we'll be able to successfully reconnect to the P2P
 * network via contacting one of them. So if that's the case, spend a
 * little longer trying to connect to known peers before querying the
 * DNS seeds.
 */
static constexpr std::chrono::seconds DNSSEEDS_DELAY_FEW_PEERS{11};
static constexpr std::chrono::minutes DNSSEEDS_DELAY_MANY_PEERS{5};
static constexpr int DNSSEEDS_DELAY_PEER_THRESHOLD = 1000; // "many" vs "few" peers

/** The default timeframe for -maxuploadtarget. 1 day. */
static constexpr std::chrono::seconds MAX_UPLOAD_TIMEFRAME{60 * 60 * 24};

// A random time period (0 to 1 seconds) is added to feeler connections to prevent synchronization.
static constexpr auto FEELER_SLEEP_WINDOW{1s};

/** Frequency to attempt extra connections to reachable networks we're not connected to yet **/
static constexpr auto EXTRA_NETWORK_PEER_INTERVAL{5min};

/** Used to pass flags to the Bind() function */
enum BindFlags {
    BF_NONE         = 0,
    BF_REPORT_ERROR = (1U << 0),
    /**
     * Do not call AddLocal() for our special addresses, e.g., for incoming
     * Tor connections, to prevent gossiping them over the network.
     */
    BF_DONT_ADVERTISE = (1U << 1),
};

// The set of sockets cannot be modified while waiting
// The sleep time needs to be small to avoid new sockets stalling
static const uint64_t SELECT_TIMEOUT_MILLISECONDS = 50;

const std::string NET_MESSAGE_TYPE_OTHER = "*other*";

static const uint64_t RANDOMIZER_ID_NETGROUP = 0x6c0edd8036ef4036ULL; // SHA256("netgroup")[0:8]
static const uint64_t RANDOMIZER_ID_LOCALHOSTNONCE = 0xd93e69e2bbfa5735ULL; // SHA256("localhostnonce")[0:8]
static const uint64_t RANDOMIZER_ID_NETWORKKEY = 0x0e8a2b136c592a7dULL; // SHA256("networkkey")[0:8]
//
// Global state variables
//
bool fDiscover = true;
bool fListen = true;
GlobalMutex g_maplocalhost_mutex;
std::map<CNetAddr, LocalServiceInfo> mapLocalHost GUARDED_BY(g_maplocalhost_mutex);
std::string strSubVersion;

size_t CSerializedNetMsg::GetMemoryUsage() const noexcept
{
    return sizeof(*this) + memusage::DynamicUsage(m_type) + memusage::DynamicUsage(data);
}

size_t CNetMessage::GetMemoryUsage() const noexcept
{
    return sizeof(*this) + memusage::DynamicUsage(m_type) + m_recv.GetMemoryUsage();
}

void CConnman::AddAddrFetch(const std::string& strDest)
{
    LOCK(m_addr_fetches_mutex);
    m_addr_fetches.push_back(strDest);
}

uint16_t GetListenPort()
{
    // If -bind= is provided with ":port" part, use that (first one if multiple are provided).
    for (const std::string& bind_arg : gArgs.GetArgs("-bind")) {
        constexpr uint16_t dummy_port = 0;

        const std::optional<CService> bind_addr{Lookup(bind_arg, dummy_port, /*fAllowLookup=*/false)};
        if (bind_addr.has_value() && bind_addr->GetPort() != dummy_port) return bind_addr->GetPort();
    }

    // Otherwise, if -whitebind= without NetPermissionFlags::NoBan is provided, use that
    // (-whitebind= is required to have ":port").
    for (const std::string& whitebind_arg : gArgs.GetArgs("-whitebind")) {
        NetWhitebindPermissions whitebind;
        bilingual_str error;
        if (NetWhitebindPermissions::TryParse(whitebind_arg, whitebind, error)) {
            if (!NetPermissions::HasFlag(whitebind.m_flags, NetPermissionFlags::NoBan)) {
                return whitebind.m_service.GetPort();
            }
        }
    }

    // Otherwise, if -port= is provided, use that. Otherwise use the default port.
    return static_cast<uint16_t>(gArgs.GetIntArg("-port", Params().GetDefaultPort()));
}

// Determine the "best" local address for a particular peer.
[[nodiscard]] static std::optional<CService> GetLocal(const CNode& peer)
{
    if (!fListen) return std::nullopt;

    std::optional<CService> addr;
    int nBestScore = -1;
    int nBestReachability = -1;
    {
        LOCK(g_maplocalhost_mutex);
        for (const auto& [local_addr, local_service_info] : mapLocalHost) {
            // For privacy reasons, don't advertise our privacy-network address
            // to other networks and don't advertise our other-network address
            // to privacy networks.
            if (local_addr.GetNetwork() != peer.ConnectedThroughNetwork()
                && (local_addr.IsPrivacyNet() || peer.IsConnectedThroughPrivacyNet())) {
                continue;
            }
            const int nScore{local_service_info.nScore};
            const int nReachability{local_addr.GetReachabilityFrom(peer.addr)};
            if (nReachability > nBestReachability || (nReachability == nBestReachability && nScore > nBestScore)) {
                addr.emplace(CService{local_addr, local_service_info.nPort});
                nBestReachability = nReachability;
                nBestScore = nScore;
            }
        }
    }
    return addr;
}

//! Convert the serialized seeds into usable address objects.
static std::vector<CAddress> ConvertSeeds(const std::vector<uint8_t> &vSeedsIn)
{
    // It'll only connect to one or two seed nodes because once it connects,
    // it'll get a pile of addresses with newer timestamps.
    // Seed nodes are given a random 'last seen time' of between one and two
    // weeks ago.
    const auto one_week{7 * 24h};
    std::vector<CAddress> vSeedsOut;
    FastRandomContext rng;
    ParamsStream s{SpanReader{vSeedsIn}, CAddress::V2_NETWORK};
    while (!s.empty()) {
        CService endpoint;
        s >> endpoint;
        CAddress addr{endpoint, SeedsServiceFlags()};
        addr.nTime = rng.rand_uniform_delay(Now<NodeSeconds>() - one_week, -one_week);
        LogDebug(BCLog::NET, "Added hardcoded seed: %s\n", addr.ToStringAddrPort());
        vSeedsOut.push_back(addr);
    }
    return vSeedsOut;
}

// Determine the "best" local address for a particular peer.
// If none, return the unroutable 0.0.0.0 but filled in with
// the normal parameters, since the IP may be changed to a useful
// one by discovery.
CService GetLocalAddress(const CNode& peer)
{
    return GetLocal(peer).value_or(CService{CNetAddr(), GetListenPort()});
}

static int GetnScore(const CService& addr)
{
    LOCK(g_maplocalhost_mutex);
    const auto it = mapLocalHost.find(addr);
    return (it != mapLocalHost.end()) ? it->second.nScore : 0;
}

// Is our peer's addrLocal potentially useful as an external IP source?
[[nodiscard]] static bool IsPeerAddrLocalGood(CNode *pnode)
{
    CService addrLocal = pnode->GetAddrLocal();
    return fDiscover && pnode->addr.IsRoutable() && addrLocal.IsRoutable() &&
           g_reachable_nets.Contains(addrLocal);
}

std::optional<CService> GetLocalAddrForPeer(CNode& node)
{
    CService addrLocal{GetLocalAddress(node)};
    // If discovery is enabled, sometimes give our peer the address it
    // tells us that it sees us as in case it has a better idea of our
    // address than we do.
    FastRandomContext rng;
    if (IsPeerAddrLocalGood(&node) && (!addrLocal.IsRoutable() ||
         rng.randbits((GetnScore(addrLocal) > LOCAL_MANUAL) ? 3 : 1) == 0))
    {
        if (node.IsInboundConn()) {
            // For inbound connections, assume both the address and the port
            // as seen from the peer.
            addrLocal = CService{node.GetAddrLocal()};
        } else {
            // For outbound connections, assume just the address as seen from
            // the peer and leave the port in `addrLocal` as returned by
            // `GetLocalAddress()` above. The peer has no way to observe our
            // listening port when we have initiated the connection.
            addrLocal.SetIP(node.GetAddrLocal());
        }
    }
    if (addrLocal.IsRoutable()) {
        LogDebug(BCLog::NET, "Advertising address %s to peer=%d\n", addrLocal.ToStringAddrPort(), node.GetId());
        return addrLocal;
    }
    // Address is unroutable. Don't advertise.
    return std::nullopt;
}

void ClearLocal()
{
    LOCK(g_maplocalhost_mutex);
    return mapLocalHost.clear();
}

// learn a new local address
bool AddLocal(const CService& addr_, int nScore)
{
    CService addr{MaybeFlipIPv6toCJDNS(addr_)};

    if (!addr.IsRoutable())
        return false;

    if (!fDiscover && nScore < LOCAL_MANUAL)
        return false;

    if (!g_reachable_nets.Contains(addr))
        return false;

    if (fLogIPs) {
        LogInfo("AddLocal(%s,%i)\n", addr.ToStringAddrPort(), nScore);
    }

    {
        LOCK(g_maplocalhost_mutex);
        const auto [it, is_newly_added] = mapLocalHost.emplace(addr, LocalServiceInfo());
        LocalServiceInfo &info = it->second;
        if (is_newly_added || nScore >= info.nScore) {
            info.nScore = nScore + (is_newly_added ? 0 : 1);
            info.nPort = addr.GetPort();
        }
    }

    return true;
}

bool AddLocal(const CNetAddr &addr, int nScore)
{
    return AddLocal(CService(addr, GetListenPort()), nScore);
}

void RemoveLocal(const CService& addr)
{
    LOCK(g_maplocalhost_mutex);
    if (fLogIPs) {
        LogInfo("RemoveLocal(%s)\n", addr.ToStringAddrPort());
    }

    mapLocalHost.erase(addr);
}

/** vote for a local address */
bool SeenLocal(const CService& addr)
{
    LOCK(g_maplocalhost_mutex);
    const auto it = mapLocalHost.find(addr);
    if (it == mapLocalHost.end()) return false;
    ++it->second.nScore;
    return true;
}


/** check whether a given address is potentially local */
bool IsLocal(const CService& addr)
{
    LOCK(g_maplocalhost_mutex);
    return mapLocalHost.contains(addr);
}

bool CConnman::AlreadyConnectedToHost(std::string_view host) const
{
    LOCK(m_nodes_mutex);
    return std::ranges::any_of(m_nodes, [&host](CNode* node) { return node->m_addr_name == host; });
}

bool CConnman::AlreadyConnectedToAddressPort(const CService& addr_port) const
{
    LOCK(m_nodes_mutex);
    return std::ranges::any_of(m_nodes, [&addr_port](CNode* node) { return node->addr == addr_port; });
}

bool CConnman::AlreadyConnectedToAddress(const CNetAddr& addr) const
{
    LOCK(m_nodes_mutex);
    return std::ranges::any_of(m_nodes, [&addr](CNode* node) { return node->addr == addr; });
}

bool CConnman::CheckIncomingNonce(uint64_t nonce)
{
    LOCK(m_nodes_mutex);
    for (const CNode* pnode : m_nodes) {
        // Omit private broadcast connections from this check to prevent this privacy attack:
        // - We connect to a peer in an attempt to privately broadcast a transaction. From our
        //   VERSION message the peer deducts that this is a short-lived connection for
        //   broadcasting a transaction, takes our nonce and delays their VERACK.
        // - The peer starts connecting to (clearnet) nodes and sends them a VERSION message
        //   which contains our nonce. If the peer manages to connect to us we would disconnect.
        // - Upon a disconnect, the peer knows our clearnet address. They go back to the short
        //   lived privacy broadcast connection and continue with VERACK.
        if (!pnode->fSuccessfullyConnected && !pnode->IsInboundConn() && !pnode->IsPrivateBroadcastConn() &&
            pnode->GetLocalNonce() == nonce)
            return false;
    }
    return true;
}

CNode* CConnman::ConnectNode(CAddress addrConnect,
                             const char* pszDest,
                             bool fCountFailure,
                             ConnectionType conn_type,
                             bool use_v2transport,
                             const std::optional<Proxy>& proxy_override)
{
    AssertLockNotHeld(m_unused_i2p_sessions_mutex);
    assert(conn_type != ConnectionType::INBOUND);

    if (pszDest == nullptr) {
        if (IsLocal(addrConnect))
            return nullptr;

        // Look for an existing connection
        if (AlreadyConnectedToAddressPort(addrConnect)) {
            LogInfo("Failed to open new connection to %s, already connected", addrConnect.ToStringAddrPort());
            return nullptr;
        }
    }

    LogDebug(BCLog::NET, "trying %s connection (%s) to %s, lastseen=%.1fhrs\n",
        use_v2transport ? "v2" : "v1",
        ConnectionTypeAsString(conn_type),
        pszDest ? pszDest : addrConnect.ToStringAddrPort(),
        Ticks<HoursDouble>(pszDest ? 0h : Now<NodeSeconds>() - addrConnect.nTime));

    // Resolve
    const uint16_t default_port{pszDest != nullptr ? GetDefaultPort(pszDest) :
                                                     m_params.GetDefaultPort()};

    // Collection of addresses to try to connect to: either all dns resolved addresses if a domain name (pszDest) is provided, or addrConnect otherwise.
    std::vector<CAddress> connect_to{};
    if (pszDest) {
        std::vector<CService> resolved{Lookup(pszDest, default_port, fNameLookup && !HaveNameProxy(), 256)};
        if (!resolved.empty()) {
            std::shuffle(resolved.begin(), resolved.end(), FastRandomContext());
            // If the connection is made by name, it can be the case that the name resolves to more than one address.
            // We don't want to connect any more of them if we are already connected to one
            for (const auto& r : resolved) {
                addrConnect = CAddress{MaybeFlipIPv6toCJDNS(r), NODE_NONE};
                if (!addrConnect.IsValid()) {
                    LogDebug(BCLog::NET, "Resolver returned invalid address %s for %s\n", addrConnect.ToStringAddrPort(), pszDest);
                    return nullptr;
                }
                // It is possible that we already have a connection to the IP/port pszDest resolved to.
                // In that case, drop the connection that was just created.
                if (AlreadyConnectedToAddressPort(addrConnect)) {
                    LogInfo("Not opening a connection to %s, already connected to %s\n", pszDest, addrConnect.ToStringAddrPort());
                    return nullptr;
                }
                // Add the address to the resolved addresses vector so we can try to connect to it later on
                connect_to.push_back(addrConnect);
            }
        } else {
            // For resolution via proxy
            connect_to.push_back(addrConnect);
        }
    } else {
        // Connect via addrConnect directly
        connect_to.push_back(addrConnect);
    }

    // Connect
    std::unique_ptr<Sock> sock;
    CService addr_bind;
    assert(!addr_bind.IsValid());
    std::unique_ptr<i2p::sam::Session> i2p_transient_session;

    for (auto& target_addr : connect_to) {
        if (target_addr.IsValid()) {
            const std::optional<Proxy> use_proxy{
                proxy_override.has_value() ? proxy_override : GetProxy(target_addr.GetNetwork()),
            };
            bool proxyConnectionFailed = false;

            if (target_addr.IsI2P() && use_proxy) {
                i2p::Connection conn;
                bool connected{false};

                // If an I2P SAM session already exists, normally we would re-use it. But in the case of
                // private broadcast we force a new transient session. A Connect() using m_i2p_sam_session
                // would use our permanent I2P address as a source address.
                if (m_i2p_sam_session && conn_type != ConnectionType::PRIVATE_BROADCAST) {
                    connected = m_i2p_sam_session->Connect(target_addr, conn, proxyConnectionFailed);
                } else {
                    {
                        LOCK(m_unused_i2p_sessions_mutex);
                        if (m_unused_i2p_sessions.empty()) {
                            i2p_transient_session =
                                std::make_unique<i2p::sam::Session>(*use_proxy, m_interrupt_net);
                        } else {
                            i2p_transient_session.swap(m_unused_i2p_sessions.front());
                            m_unused_i2p_sessions.pop();
                        }
                    }
                    connected = i2p_transient_session->Connect(target_addr, conn, proxyConnectionFailed);
                    if (!connected) {
                        LOCK(m_unused_i2p_sessions_mutex);
                        if (m_unused_i2p_sessions.size() < MAX_UNUSED_I2P_SESSIONS_SIZE) {
                            m_unused_i2p_sessions.emplace(i2p_transient_session.release());
                        }
                    }
                }

                if (connected) {
                    sock = std::move(conn.sock);
                    addr_bind = conn.me;
                }
            } else if (use_proxy) {
                LogDebug(BCLog::PROXY, "Using proxy: %s to connect to %s\n", use_proxy->ToString(), target_addr.ToStringAddrPort());
                sock = ConnectThroughProxy(*use_proxy, target_addr.ToStringAddr(), target_addr.GetPort(), proxyConnectionFailed);
            } else {
                // no proxy needed (none set for target network)
                sock = ConnectDirectly(target_addr, conn_type == ConnectionType::MANUAL);
            }
            if (!proxyConnectionFailed) {
                // If a connection to the node was attempted, and failure (if any) is not caused by a problem connecting to
                // the proxy, mark this as an attempt.
                addrman.get().Attempt(target_addr, fCountFailure);
            }
        } else if (pszDest) {
            if (const auto name_proxy = GetNameProxy()) {
                std::string host;
                uint16_t port{default_port};
                SplitHostPort(pszDest, port, host);
                bool proxyConnectionFailed;
                sock = ConnectThroughProxy(*name_proxy, host, port, proxyConnectionFailed);
            }
        }
        // Check any other resolved address (if any) if we fail to connect
        if (!sock) {
            continue;
        }

        NetPermissionFlags permission_flags = NetPermissionFlags::None;
        std::vector<NetWhitelistPermissions> whitelist_permissions = conn_type == ConnectionType::MANUAL ? vWhitelistedRangeOutgoing : std::vector<NetWhitelistPermissions>{};
        AddWhitelistPermissionFlags(permission_flags, target_addr, whitelist_permissions);

        // Add node
        NodeId id = GetNewNodeId();
        uint64_t nonce = GetDeterministicRandomizer(RANDOMIZER_ID_LOCALHOSTNONCE).Write(id).Finalize();
        if (!addr_bind.IsValid()) {
            addr_bind = GetBindAddress(*sock);
        }
        uint64_t network_id = GetDeterministicRandomizer(RANDOMIZER_ID_NETWORKKEY)
                            .Write(target_addr.GetNetClass())
                            .Write(addr_bind.GetAddrBytes())
                            // For outbound connections, the port of the bound address is randomly
                            // assigned by the OS and would therefore not be useful for seeding.
                            .Write(0)
                            .Finalize();
        CNode* pnode = new CNode(id,
                                std::move(sock),
                                target_addr,
                                CalculateKeyedNetGroup(target_addr),
                                nonce,
                                addr_bind,
                                pszDest ? pszDest : "",
                                conn_type,
                                /*inbound_onion=*/false,
                                network_id,
                                CNodeOptions{
                                    .permission_flags = permission_flags,
                                    .i2p_sam_session = std::move(i2p_transient_session),
                                    .recv_flood_size = nReceiveFloodSize,
                                    .use_v2transport = use_v2transport,
                                });
        pnode->AddRef();

        // We're making a new connection, harvest entropy from the time (and our peer count)
        RandAddEvent((uint32_t)id);

        return pnode;
    }

    return nullptr;
}

void CNode::CloseSocketDisconnect()
{
    fDisconnect = true;
    LOCK(m_sock_mutex);
    if (m_sock) {
        LogDebug(BCLog::NET, "Resetting socket for %s", LogPeer());
        m_sock.reset();

        TRACEPOINT(net, closed_connection,
            GetId(),
            m_addr_name.c_str(),
            ConnectionTypeAsString().c_str(),
            ConnectedThroughNetwork(),
            Ticks<std::chrono::seconds>(m_connected));
    }
    m_i2p_sam_session.reset();
}

void CConnman::AddWhitelistPermissionFlags(NetPermissionFlags& flags, std::optional<CNetAddr> addr, const std::vector<NetWhitelistPermissions>& ranges) const {
    for (const auto& subnet : ranges) {
        if (addr.has_value() && subnet.m_subnet.Match(addr.value())) {
            NetPermissions::AddFlag(flags, subnet.m_flags);
        }
    }
    if (NetPermissions::HasFlag(flags, NetPermissionFlags::Implicit)) {
        NetPermissions::ClearFlag(flags, NetPermissionFlags::Implicit);
        if (whitelist_forcerelay) NetPermissions::AddFlag(flags, NetPermissionFlags::ForceRelay);
        if (whitelist_relay) NetPermissions::AddFlag(flags, NetPermissionFlags::Relay);
        NetPermissions::AddFlag(flags, NetPermissionFlags::Mempool);
        NetPermissions::AddFlag(flags, NetPermissionFlags::NoBan);
    }
}

CService CNode::GetAddrLocal() const
{
    AssertLockNotHeld(m_addr_local_mutex);
    LOCK(m_addr_local_mutex);
    return m_addr_local;
}

void CNode::SetAddrLocal(const CService& addrLocalIn) {
    AssertLockNotHeld(m_addr_local_mutex);
    LOCK(m_addr_local_mutex);
    if (Assume(!m_addr_local.IsValid())) { // Addr local can only be set once during version msg processing
        m_addr_local = addrLocalIn;
    }
}

Network CNode::ConnectedThroughNetwork() const
{
    return m_inbound_onion ? NET_ONION : addr.GetNetClass();
}

bool CNode::IsConnectedThroughPrivacyNet() const
{
    return m_inbound_onion || addr.IsPrivacyNet();
}

#undef X
#define X(name) stats.name = name
void CNode::CopyStats(CNodeStats& stats)
{
    stats.nodeid = this->GetId();
    X(addr);
    X(addrBind);
    stats.m_network = ConnectedThroughNetwork();
    X(m_last_send);
    X(m_last_recv);
    X(m_last_tx_time);
    X(m_last_block_time);
    X(m_connected);
    X(m_addr_name);
    X(nVersion);
    {
        LOCK(m_subver_mutex);
        X(cleanSubVer);
    }
    stats.fInbound = IsInboundConn();
    X(m_bip152_highbandwidth_to);
    X(m_bip152_highbandwidth_from);
    {
        LOCK(cs_vSend);
        X(mapSendBytesPerMsgType);
        X(nSendBytes);
    }
    {
        LOCK(cs_vRecv);
        X(mapRecvBytesPerMsgType);
        X(nRecvBytes);
        Transport::Info info = m_transport->GetInfo();
        stats.m_transport_type = info.transport_type;
        if (info.session_id) stats.m_session_id = HexStr(*info.session_id);
    }
    X(m_permission_flags);

    X(m_last_ping_time);
    X(m_min_ping_time);

    // Leave string empty if addrLocal invalid (not filled in yet)
    CService addrLocalUnlocked = GetAddrLocal();
    stats.addrLocal = addrLocalUnlocked.IsValid() ? addrLocalUnlocked.ToStringAddrPort() : "";

    X(m_conn_type);
}
#undef X

bool CNode::ReceiveMsgBytes(std::span<const uint8_t> msg_bytes, bool& complete)
{
    complete = false;
    const auto time = GetTime<std::chrono::microseconds>();
    LOCK(cs_vRecv);
    m_last_recv = std::chrono::duration_cast<std::chrono::seconds>(time);
    nRecvBytes += msg_bytes.size();
    while (msg_bytes.size() > 0) {
        // absorb network data
        if (!m_transport->ReceivedBytes(msg_bytes)) {
            // Serious transport problem, disconnect from the peer.
            return false;
        }

        if (m_transport->ReceivedMessageComplete()) {
            // decompose a transport agnostic CNetMessage from the deserializer
            bool reject_message{false};
            CNetMessage msg = m_transport->GetReceivedMessage(time, reject_message);
            if (reject_message) {
                // Message deserialization failed. Drop the message but don't disconnect the peer.
                // store the size of the corrupt message
                mapRecvBytesPerMsgType.at(NET_MESSAGE_TYPE_OTHER) += msg.m_raw_message_size;
                continue;
            }

            // Store received bytes per message type.
            // To prevent a memory DOS, only allow known message types.
            auto i = mapRecvBytesPerMsgType.find(msg.m_type);
            if (i == mapRecvBytesPerMsgType.end()) {
                i = mapRecvBytesPerMsgType.find(NET_MESSAGE_TYPE_OTHER);
            }
            assert(i != mapRecvBytesPerMsgType.end());
            i->second += msg.m_raw_message_size;

            // push the message to the process queue,
            vRecvMsg.push_back(std::move(msg));

            complete = true;
        }
    }

    return true;
}

std::string CNode::LogPeer() const
{
    auto peer_info{strprintf("peer=%d", GetId())};
    if (fLogIPs) {
        return strprintf("%s, peeraddr=%s", peer_info, addr.ToStringAddrPort());
    } else {
        return peer_info;
    }
}

std::string CNode::DisconnectMsg() const
{
    return strprintf("disconnecting %s", LogPeer());
}

V1Transport::V1Transport(const NodeId node_id) noexcept
    : m_magic_bytes{Params().MessageStart()}, m_node_id{node_id}
{
    LOCK(m_recv_mutex);
    Reset();
}

Transport::Info V1Transport::GetInfo() const noexcept
{
    return {.transport_type = TransportProtocolType::V1, .session_id = {}};
}

int V1Transport::readHeader(std::span<const uint8_t> msg_bytes)
{
    AssertLockHeld(m_recv_mutex);
    // copy data to temporary parsing buffer
    unsigned int nRemaining = CMessageHeader::HEADER_SIZE - nHdrPos;
    unsigned int nCopy = std::min<unsigned int>(nRemaining, msg_bytes.size());

    memcpy(&hdrbuf[nHdrPos], msg_bytes.data(), nCopy);
    nHdrPos += nCopy;

    // if header incomplete, exit
    if (nHdrPos < CMessageHeader::HEADER_SIZE)
        return nCopy;

    // deserialize to CMessageHeader
    try {
        hdrbuf >> hdr;
    }
    catch (const std::exception&) {
        LogDebug(BCLog::NET, "Header error: Unable to deserialize, peer=%d\n", m_node_id);
        return -1;
    }

    // Check start string, network magic
    if (hdr.pchMessageStart != m_magic_bytes) {
        LogDebug(BCLog::NET, "Header error: Wrong MessageStart %s received, peer=%d\n", HexStr(hdr.pchMessageStart), m_node_id);
        return -1;
    }

    // reject messages larger than MAX_SIZE or MAX_PROTOCOL_MESSAGE_LENGTH
    // NOTE: failing to perform this check previously allowed a malicious peer to make us allocate 32MiB of memory per
    // connection. See https://bitcoincore.org/en/2024/07/03/disclose_receive_buffer_oom.
    if (hdr.nMessageSize > MAX_SIZE || hdr.nMessageSize > MAX_PROTOCOL_MESSAGE_LENGTH) {
        LogDebug(BCLog::NET, "Header error: Size too large (%s, %u bytes), peer=%d\n", SanitizeString(hdr.GetMessageType()), hdr.nMessageSize, m_node_id);
        return -1;
    }

    // switch state to reading message data
    in_data = true;

    return nCopy;
}

int V1Transport::readData(std::span<const uint8_t> msg_bytes)
{
    AssertLockHeld(m_recv_mutex);
    unsigned int nRemaining = hdr.nMessageSize - nDataPos;
    unsigned int nCopy = std::min<unsigned int>(nRemaining, msg_bytes.size());

    if (vRecv.size() < nDataPos + nCopy) {
        // Allocate up to 256 KiB ahead, but never more than the total message size.
        vRecv.resize(std::min(hdr.nMessageSize, nDataPos + nCopy + 256 * 1024));
    }

    hasher.Write(msg_bytes.first(nCopy));
    memcpy(&vRecv[nDataPos], msg_bytes.data(), nCopy);
    nDataPos += nCopy;

    return nCopy;
}

const uint256& V1Transport::GetMessageHash() const
{
    AssertLockHeld(m_recv_mutex);
    assert(CompleteInternal());
    if (data_hash.IsNull())
        hasher.Finalize(data_hash);
    return data_hash;
}

CNetMessage V1Transport::GetReceivedMessage(const std::chrono::microseconds time, bool& reject_message)
{
    AssertLockNotHeld(m_recv_mutex);
    // Initialize out parameter
    reject_message = false;
    // decompose a single CNetMessage from the TransportDeserializer
    LOCK(m_recv_mutex);
    CNetMessage msg(std::move(vRecv));

    // store message type string, time, and sizes
    msg.m_type = hdr.GetMessageType();
    msg.m_time = time;
    msg.m_message_size = hdr.nMessageSize;
    msg.m_raw_message_size = hdr.nMessageSize + CMessageHeader::HEADER_SIZE;

    uint256 hash = GetMessageHash();

    // We just received a message off the wire, harvest entropy from the time (and the message checksum)
    RandAddEvent(ReadLE32(hash.begin()));

    // Check checksum and header message type string
    if (memcmp(hash.begin(), hdr.pchChecksum, CMessageHeader::CHECKSUM_SIZE) != 0) {
        LogDebug(BCLog::NET, "Header error: Wrong checksum (%s, %u bytes), expected %s was %s, peer=%d\n",
                 SanitizeString(msg.m_type), msg.m_message_size,
                 HexStr(std::span{hash}.first(CMessageHeader::CHECKSUM_SIZE)),
                 HexStr(hdr.pchChecksum),
                 m_node_id);
        reject_message = true;
    } else if (!hdr.IsMessageTypeValid()) {
        LogDebug(BCLog::NET, "Header error: Invalid message type (%s, %u bytes), peer=%d\n",
                 SanitizeString(hdr.GetMessageType()), msg.m_message_size, m_node_id);
        reject_message = true;
    }

    // Always reset the network deserializer (prepare for the next message)
    Reset();
    return msg;
}

bool V1Transport::SetMessageToSend(CSerializedNetMsg& msg) noexcept
{
    AssertLockNotHeld(m_send_mutex);
    // Determine whether a new message can be set.
    LOCK(m_send_mutex);
    if (m_sending_header || m_bytes_sent < m_message_to_send.data.size()) return false;

    // create dbl-sha256 checksum
    uint256 hash = Hash(msg.data);

    // create header
    CMessageHeader hdr(m_magic_bytes, msg.m_type.c_str(), msg.data.size());
    memcpy(hdr.pchChecksum, hash.begin(), CMessageHeader::CHECKSUM_SIZE);

    // serialize header
    m_header_to_send.clear();
    VectorWriter{m_header_to_send, 0, hdr};

    // update state
    m_message_to_send = std::move(msg);
    m_sending_header = true;
    m_bytes_sent = 0;
    return true;
}

Transport::BytesToSend V1Transport::GetBytesToSend(bool have_next_message) const noexcept
{
    AssertLockNotHeld(m_send_mutex);
    LOCK(m_send_mutex);
    if (m_sending_header) {
        return {std::span{m_header_to_send}.subspan(m_bytes_sent),
                // We have more to send after the header if the message has payload, or if there
                // is a next message after that.
                have_next_message || !m_message_to_send.data.empty(),
                m_message_to_send.m_type
               };
    } else {
        return {std::span{m_message_to_send.data}.subspan(m_bytes_sent),
                // We only have more to send after this message's payload if there is another
                // message.
                have_next_message,
                m_message_to_send.m_type
               };
    }
}

void V1Transport::MarkBytesSent(size_t bytes_sent) noexcept
{
    AssertLockNotHeld(m_send_mutex);
    LOCK(m_send_mutex);
    m_bytes_sent += bytes_sent;
    if (m_sending_header && m_bytes_sent == m_header_to_send.size()) {
        // We're done sending a message's header. Switch to sending its data bytes.
        m_sending_header = false;
        m_bytes_sent = 0;
    } else if (!m_sending_header && m_bytes_sent == m_message_to_send.data.size()) {
        // We're done sending a message's data. Wipe the data vector to reduce memory consumption.
        ClearShrink(m_message_to_send.data);
        m_bytes_sent = 0;
    }
}

size_t V1Transport::GetSendMemoryUsage() const noexcept
{
    AssertLockNotHeld(m_send_mutex);
    LOCK(m_send_mutex);
    // Don't count sending-side fields besides m_message_to_send, as they're all small and bounded.
    return m_message_to_send.GetMemoryUsage();
}

namespace {

/** List of short messages as defined in BIP324, in order.
 *
 * Only message types that are actually implemented in this codebase need to be listed, as other
 * messages get ignored anyway - whether we know how to decode them or not.
 */
const std::array<std::string, 33> V2_MESSAGE_IDS = {
    "", // 12 bytes follow encoding the message type like in V1
    NetMsgType::ADDR,
    NetMsgType::BLOCK,
    NetMsgType::BLOCKTXN,
    NetMsgType::CMPCTBLOCK,
    NetMsgType::FEEFILTER,
    NetMsgType::FILTERADD,
    NetMsgType::FILTERCLEAR,
    NetMsgType::FILTERLOAD,
    NetMsgType::GETBLOCKS,
    NetMsgType::GETBLOCKTXN,
    NetMsgType::GETDATA,
    NetMsgType::GETHEADERS,
    NetMsgType::HEADERS,
    NetMsgType::INV,
    NetMsgType::MEMPOOL,
    NetMsgType::MERKLEBLOCK,
    NetMsgType::NOTFOUND,
    NetMsgType::PING,
    NetMsgType::PONG,
    NetMsgType::SENDCMPCT,
    NetMsgType::TX,
    NetMsgType::GETCFILTERS,
    NetMsgType::CFILTER,
    NetMsgType::GETCFHEADERS,
    NetMsgType::CFHEADERS,
    NetMsgType::GETCFCHECKPT,
    NetMsgType::CFCHECKPT,
    NetMsgType::ADDRV2,
    // Unimplemented message types that are assigned in BIP324:
    "",
    "",
    "",
    ""
};

class V2MessageMap
{
    std::unordered_map<std::string, uint8_t> m_map;

public:
    V2MessageMap() noexcept
    {
        for (size_t i = 1; i < std::size(V2_MESSAGE_IDS); ++i) {
            m_map.emplace(V2_MESSAGE_IDS[i], i);
        }
    }

    std::optional<uint8_t> operator()(const std::string& message_name) const noexcept
    {
        auto it = m_map.find(message_name);
        if (it == m_map.end()) return std::nullopt;
        return it->second;
    }
};

const V2MessageMap V2_MESSAGE_MAP;

std::vector<uint8_t> GenerateRandomGarbage() noexcept
{
    std::vector<uint8_t> ret;
    FastRandomContext rng;
    ret.resize(rng.randrange(V2Transport::MAX_GARBAGE_LEN + 1));
    rng.fillrand(MakeWritableByteSpan(ret));
    return ret;
}

} // namespace

void V2Transport::StartSendingHandshake() noexcept
{
    AssertLockHeld(m_send_mutex);
    Assume(m_send_state == SendState::AWAITING_KEY);
    Assume(m_send_buffer.empty());
    // Initialize the send buffer with ellswift pubkey + provided garbage.
    m_send_buffer.resize(EllSwiftPubKey::size() + m_send_garbage.size());
    std::copy(std::begin(m_cipher.GetOurPubKey()), std::end(m_cipher.GetOurPubKey()), MakeWritableByteSpan(m_send_buffer).begin());
    std::copy(m_send_garbage.begin(), m_send_garbage.end(), m_send_buffer.begin() + EllSwiftPubKey::size());
    // We cannot wipe m_send_garbage as it will still be used as AAD later in the handshake.
}

V2Transport::V2Transport(NodeId nodeid, bool initiating, const CKey& key, std::span<const std::byte> ent32, std::vector<uint8_t> garbage) noexcept
    : m_cipher{key, ent32},
      m_initiating{initiating},
      m_nodeid{nodeid},
      m_v1_fallback{nodeid},
      m_recv_state{initiating ? RecvState::KEY : RecvState::KEY_MAYBE_V1},
      m_send_garbage{std::move(garbage)},
      m_send_state{initiating ? SendState::AWAITING_KEY : SendState::MAYBE_V1}
{
    Assume(m_send_garbage.size() <= MAX_GARBAGE_LEN);
    // Start sending immediately if we're the initiator of the connection.
    if (initiating) {
        LOCK(m_send_mutex);
        StartSendingHandshake();
    }
}

V2Transport::V2Transport(NodeId nodeid, bool initiating) noexcept
    : V2Transport{nodeid, initiating, GenerateRandomKey(),
                  MakeByteSpan(GetRandHash()), GenerateRandomGarbage()} {}

void V2Transport::SetReceiveState(RecvState recv_state) noexcept
{
    AssertLockHeld(m_recv_mutex);
    // Enforce allowed state transitions.
    switch (m_recv_state) {
    case RecvState::KEY_MAYBE_V1:
        Assume(recv_state == RecvState::KEY || recv_state == RecvState::V1);
        break;
    case RecvState::KEY:
        Assume(recv_state == RecvState::GARB_GARBTERM);
        break;
    case RecvState::GARB_GARBTERM:
        Assume(recv_state == RecvState::VERSION);
        break;
    case RecvState::VERSION:
        Assume(recv_state == RecvState::APP);
        break;
    case RecvState::APP:
        Assume(recv_state == RecvState::APP_READY);
        break;
    case RecvState::APP_READY:
        Assume(recv_state == RecvState::APP);
        break;
    case RecvState::V1:
        Assume(false); // V1 state cannot be left
        break;
    }
    // Change state.
    m_recv_state = recv_state;
}

void V2Transport::SetSendState(SendState send_state) noexcept
{
    AssertLockHeld(m_send_mutex);
    // Enforce allowed state transitions.
    switch (m_send_state) {
    case SendState::MAYBE_V1:
        Assume(send_state == SendState::V1 || send_state == SendState::AWAITING_KEY);
        break;
    case SendState::AWAITING_KEY:
        Assume(send_state == SendState::READY);
        break;
    case SendState::READY:
    case SendState::V1:
        Assume(false); // Final states
        break;
    }
    // Change state.
    m_send_state = send_state;
}

bool V2Transport::ReceivedMessageComplete() const noexcept
{
    AssertLockNotHeld(m_recv_mutex);
    LOCK(m_recv_mutex);
    if (m_recv_state == RecvState::V1) return m_v1_fallback.ReceivedMessageComplete();

    return m_recv_state == RecvState::APP_READY;
}

void V2Transport::ProcessReceivedMaybeV1Bytes() noexcept
{
    AssertLockHeld(m_recv_mutex);
    AssertLockNotHeld(m_send_mutex);
    Assume(m_recv_state == RecvState::KEY_MAYBE_V1);
    // We still have to determine if this is a v1 or v2 connection. The bytes being received could
    // be the beginning of either a v1 packet (network magic + "version\x00\x00\x00\x00\x00"), or
    // of a v2 public key. BIP324 specifies that a mismatch with this 16-byte string should trigger
    // sending of the key.
    std::array<uint8_t, V1_PREFIX_LEN> v1_prefix = {0, 0, 0, 0, 'v', 'e', 'r', 's', 'i', 'o', 'n', 0, 0, 0, 0, 0};
    std::copy(std::begin(Params().MessageStart()), std::end(Params().MessageStart()), v1_prefix.begin());
    Assume(m_recv_buffer.size() <= v1_prefix.size());
    if (!std::equal(m_recv_buffer.begin(), m_recv_buffer.end(), v1_prefix.begin())) {
        // Mismatch with v1 prefix, so we can assume a v2 connection.
        SetReceiveState(RecvState::KEY); // Convert to KEY state, leaving received bytes around.
        // Transition the sender to AWAITING_KEY state and start sending.
        LOCK(m_send_mutex);
        SetSendState(SendState::AWAITING_KEY);
        StartSendingHandshake();
    } else if (m_recv_buffer.size() == v1_prefix.size()) {
        // Full match with the v1 prefix, so fall back to v1 behavior.
        LOCK(m_send_mutex);
        std::span<const uint8_t> feedback{m_recv_buffer};
        // Feed already received bytes to v1 transport. It should always accept these, because it's
        // less than the size of a v1 header, and these are the first bytes fed to m_v1_fallback.
        bool ret = m_v1_fallback.ReceivedBytes(feedback);
        Assume(feedback.empty());
        Assume(ret);
        SetReceiveState(RecvState::V1);
        SetSendState(SendState::V1);
        // Reset v2 transport buffers to save memory.
        ClearShrink(m_recv_buffer);
        ClearShrink(m_send_buffer);
    } else {
        // We have not received enough to distinguish v1 from v2 yet. Wait until more bytes come.
    }
}

bool V2Transport::ProcessReceivedKeyBytes() noexcept
{
    AssertLockHeld(m_recv_mutex);
    AssertLockNotHeld(m_send_mutex);
    Assume(m_recv_state == RecvState::KEY);
    Assume(m_recv_buffer.size() <= EllSwiftPubKey::size());

    // As a special exception, if bytes 4-16 of the key on a responder connection match the
    // corresponding bytes of a V1 version message, but bytes 0-4 don't match the network magic
    // (if they did, we'd have switched to V1 state already), assume this is a peer from
    // another network, and disconnect them. They will almost certainly disconnect us too when
    // they receive our uniformly random key and garbage, but detecting this case specially
    // means we can log it.
    static constexpr std::array<uint8_t, 12> MATCH = {'v', 'e', 'r', 's', 'i', 'o', 'n', 0, 0, 0, 0, 0};
    static constexpr size_t OFFSET = std::tuple_size_v<MessageStartChars>;
    if (!m_initiating && m_recv_buffer.size() >= OFFSET + MATCH.size()) {
        if (std::equal(MATCH.begin(), MATCH.end(), m_recv_buffer.begin() + OFFSET)) {
            LogDebug(BCLog::NET, "V2 transport error: V1 peer with wrong MessageStart %s\n",
                     HexStr(std::span(m_recv_buffer).first(OFFSET)));
            return false;
        }
    }

    if (m_recv_buffer.size() == EllSwiftPubKey::size()) {
        // Other side's key has been fully received, and can now be Diffie-Hellman combined with
        // our key to initialize the encryption ciphers.

        // Initialize the ciphers.
        EllSwiftPubKey ellswift(MakeByteSpan(m_recv_buffer));
        LOCK(m_send_mutex);
        m_cipher.Initialize(ellswift, m_initiating);

        // Switch receiver state to GARB_GARBTERM.
        SetReceiveState(RecvState::GARB_GARBTERM);
        m_recv_buffer.clear();

        // Switch sender state to READY.
        SetSendState(SendState::READY);

        // Append the garbage terminator to the send buffer.
        m_send_buffer.resize(m_send_buffer.size() + BIP324Cipher::GARBAGE_TERMINATOR_LEN);
        std::copy(m_cipher.GetSendGarbageTerminator().begin(),
                  m_cipher.GetSendGarbageTerminator().end(),
                  MakeWritableByteSpan(m_send_buffer).last(BIP324Cipher::GARBAGE_TERMINATOR_LEN).begin());

        // Construct version packet in the send buffer, with the sent garbage data as AAD.
        m_send_buffer.resize(m_send_buffer.size() + BIP324Cipher::EXPANSION + VERSION_CONTENTS.size());
        m_cipher.Encrypt(
            /*contents=*/VERSION_CONTENTS,
            /*aad=*/MakeByteSpan(m_send_garbage),
            /*ignore=*/false,
            /*output=*/MakeWritableByteSpan(m_send_buffer).last(BIP324Cipher::EXPANSION + VERSION_CONTENTS.size()));
        // We no longer need the garbage.
        ClearShrink(m_send_garbage);
    } else {
        // We still have to receive more key bytes.
    }
    return true;
}

bool V2Transport::ProcessReceivedGarbageBytes() noexcept
{
    AssertLockHeld(m_recv_mutex);
    Assume(m_recv_state == RecvState::GARB_GARBTERM);
    Assume(m_recv_buffer.size() <= MAX_GARBAGE_LEN + BIP324Cipher::GARBAGE_TERMINATOR_LEN);
    if (m_recv_buffer.size() >= BIP324Cipher::GARBAGE_TERMINATOR_LEN) {
        if (std::ranges::equal(MakeByteSpan(m_recv_buffer).last(BIP324Cipher::GARBAGE_TERMINATOR_LEN), m_cipher.GetReceiveGarbageTerminator())) {
            // Garbage terminator received. Store garbage to authenticate it as AAD later.
            m_recv_aad = std::move(m_recv_buffer);
            m_recv_aad.resize(m_recv_aad.size() - BIP324Cipher::GARBAGE_TERMINATOR_LEN);
            m_recv_buffer.clear();
            SetReceiveState(RecvState::VERSION);
        } else if (m_recv_buffer.size() == MAX_GARBAGE_LEN + BIP324Cipher::GARBAGE_TERMINATOR_LEN) {
            // We've reached the maximum length for garbage + garbage terminator, and the
            // terminator still does not match. Abort.
            LogDebug(BCLog::NET, "V2 transport error: missing garbage terminator, peer=%d\n", m_nodeid);
            return false;
        } else {
            // We still need to receive more garbage and/or garbage terminator bytes.
        }
    } else {
        // We have less than GARBAGE_TERMINATOR_LEN (16) bytes, so we certainly need to receive
        // more first.
    }
    return true;
}

bool V2Transport::ProcessReceivedPacketBytes() noexcept
{
    AssertLockHeld(m_recv_mutex);
    Assume(m_recv_state == RecvState::VERSION || m_recv_state == RecvState::APP);

    // The maximum permitted contents length for a packet, consisting of:
    // - 0x00 byte: indicating long message type encoding
    // - 12 bytes of message type
    // - payload
    static constexpr size_t MAX_CONTENTS_LEN =
        1 + CMessageHeader::MESSAGE_TYPE_SIZE +
        std::min<size_t>(MAX_SIZE, MAX_PROTOCOL_MESSAGE_LENGTH);

    if (m_recv_buffer.size() == BIP324Cipher::LENGTH_LEN) {
        // Length descriptor received.
        m_recv_len = m_cipher.DecryptLength(MakeByteSpan(m_recv_buffer));
        if (m_recv_len > MAX_CONTENTS_LEN) {
            LogDebug(BCLog::NET, "V2 transport error: packet too large (%u bytes), peer=%d\n", m_recv_len, m_nodeid);
            return false;
        }
    } else if (m_recv_buffer.size() > BIP324Cipher::LENGTH_LEN && m_recv_buffer.size() == m_recv_len + BIP324Cipher::EXPANSION) {
        // Ciphertext received, decrypt it into m_recv_decode_buffer.
        // Note that it is impossible to reach this branch without hitting the branch above first,
        // as GetMaxBytesToProcess only allows up to LENGTH_LEN into the buffer before that point.
        m_recv_decode_buffer.resize(m_recv_len);
        bool ignore{false};
        bool ret = m_cipher.Decrypt(
            /*input=*/MakeByteSpan(m_recv_buffer).subspan(BIP324Cipher::LENGTH_LEN),
            /*aad=*/MakeByteSpan(m_recv_aad),
            /*ignore=*/ignore,
            /*contents=*/MakeWritableByteSpan(m_recv_decode_buffer));
        if (!ret) {
            LogDebug(BCLog::NET, "V2 transport error: packet decryption failure (%u bytes), peer=%d\n", m_recv_len, m_nodeid);
            return false;
        }
        // We have decrypted a valid packet with the AAD we expected, so clear the expected AAD.
        ClearShrink(m_recv_aad);
        // Feed the last 4 bytes of the Poly1305 authentication tag (and its timing) into our RNG.
        RandAddEvent(ReadLE32(m_recv_buffer.data() + m_recv_buffer.size() - 4));

        // At this point we have a valid packet decrypted into m_recv_decode_buffer. If it's not a
        // decoy, which we simply ignore, use the current state to decide what to do with it.
        if (!ignore) {
            switch (m_recv_state) {
            case RecvState::VERSION:
                // Version message received; transition to application phase. The contents is
                // ignored, but can be used for future extensions.
                SetReceiveState(RecvState::APP);
                break;
            case RecvState::APP:
                // Application message decrypted correctly. It can be extracted using GetMessage().
                SetReceiveState(RecvState::APP_READY);
                break;
            default:
                // Any other state is invalid (this function should not have been called).
                Assume(false);
            }
        }
        // Wipe the receive buffer where the next packet will be received into.
        ClearShrink(m_recv_buffer);
        // In all but APP_READY state, we can wipe the decoded contents.
        if (m_recv_state != RecvState::APP_READY) ClearShrink(m_recv_decode_buffer);
    } else {
        // We either have less than 3 bytes, so we don't know the packet's length yet, or more
        // than 3 bytes but less than the packet's full ciphertext. Wait until those arrive.
    }
    return true;
}

size_t V2Transport::GetMaxBytesToProcess() noexcept
{
    AssertLockHeld(m_recv_mutex);
    switch (m_recv_state) {
    case RecvState::KEY_MAYBE_V1:
        // During the KEY_MAYBE_V1 state we do not allow more than the length of v1 prefix into the
        // receive buffer.
        Assume(m_recv_buffer.size() <= V1_PREFIX_LEN);
        // As long as we're not sure if this is a v1 or v2 connection, don't receive more than what
        // is strictly necessary to distinguish the two (16 bytes). If we permitted more than
        // the v1 header size (24 bytes), we may not be able to feed the already-received bytes
        // back into the m_v1_fallback V1 transport.
        return V1_PREFIX_LEN - m_recv_buffer.size();
    case RecvState::KEY:
        // During the KEY state, we only allow the 64-byte key into the receive buffer.
        Assume(m_recv_buffer.size() <= EllSwiftPubKey::size());
        // As long as we have not received the other side's public key, don't receive more than
        // that (64 bytes), as garbage follows, and locating the garbage terminator requires the
        // key exchange first.
        return EllSwiftPubKey::size() - m_recv_buffer.size();
    case RecvState::GARB_GARBTERM:
        // Process garbage bytes one by one (because terminator may appear anywhere).
        return 1;
    case RecvState::VERSION:
    case RecvState::APP:
        // These three states all involve decoding a packet. Process the length descriptor first,
        // so that we know where the current packet ends (and we don't process bytes from the next
        // packet or decoy yet). Then, process the ciphertext bytes of the current packet.
        if (m_recv_buffer.size() < BIP324Cipher::LENGTH_LEN) {
            return BIP324Cipher::LENGTH_LEN - m_recv_buffer.size();
        } else {
            // Note that BIP324Cipher::EXPANSION is the total difference between contents size
            // and encoded packet size, which includes the 3 bytes due to the packet length.
            // When transitioning from receiving the packet length to receiving its ciphertext,
            // the encrypted packet length is left in the receive buffer.
            return BIP324Cipher::EXPANSION + m_recv_len - m_recv_buffer.size();
        }
    case RecvState::APP_READY:
        // No bytes can be processed until GetMessage() is called.
        return 0;
    case RecvState::V1:
        // Not allowed (must be dealt with by the caller).
        Assume(false);
        return 0;
    }
    Assume(false); // unreachable
    return 0;
}

bool V2Transport::ReceivedBytes(std::span<const uint8_t>& msg_bytes) noexcept
{
    AssertLockNotHeld(m_recv_mutex);
    /** How many bytes to allocate in the receive buffer at most above what is received so far. */
    static constexpr size_t MAX_RESERVE_AHEAD = 256 * 1024;

    LOCK(m_recv_mutex);
    if (m_recv_state == RecvState::V1) return m_v1_fallback.ReceivedBytes(msg_bytes);

    // Process the provided bytes in msg_bytes in a loop. In each iteration a nonzero number of
    // bytes (decided by GetMaxBytesToProcess) are taken from the beginning om msg_bytes, and
    // appended to m_recv_buffer. Then, depending on the receiver state, one of the
    // ProcessReceived*Bytes functions is called to process the bytes in that buffer.
    while (!msg_bytes.empty()) {
        // Decide how many bytes to copy from msg_bytes to m_recv_buffer.
        size_t max_read = GetMaxBytesToProcess();

        // Reserve space in the buffer if there is not enough.
        if (m_recv_buffer.size() + std::min(msg_bytes.size(), max_read) > m_recv_buffer.capacity()) {
            switch (m_recv_state) {
            case RecvState::KEY_MAYBE_V1:
            case RecvState::KEY:
            case RecvState::GARB_GARBTERM:
                // During the initial states (key/garbage), allocate once to fit the maximum (4111
                // bytes).
                m_recv_buffer.reserve(MAX_GARBAGE_LEN + BIP324Cipher::GARBAGE_TERMINATOR_LEN);
                break;
            case RecvState::VERSION:
            case RecvState::APP: {
                // During states where a packet is being received, as much as is expected but never
                // more than MAX_RESERVE_AHEAD bytes in addition to what is received so far.
                // This means attackers that want to cause us to waste allocated memory are limited
                // to MAX_RESERVE_AHEAD above the largest allowed message contents size, and to
                // MAX_RESERVE_AHEAD more than they've actually sent us.
                size_t alloc_add = std::min(max_read, msg_bytes.size() + MAX_RESERVE_AHEAD);
                m_recv_buffer.reserve(m_recv_buffer.size() + alloc_add);
                break;
            }
            case RecvState::APP_READY:
                // The buffer is empty in this state.
                Assume(m_recv_buffer.empty());
                break;
            case RecvState::V1:
                // Should have bailed out above.
                Assume(false);
                break;
            }
        }

        // Can't read more than provided input.
        max_read = std::min(msg_bytes.size(), max_read);
        // Copy data to buffer.
        m_recv_buffer.insert(m_recv_buffer.end(), UCharCast(msg_bytes.data()), UCharCast(msg_bytes.data() + max_read));
        msg_bytes = msg_bytes.subspan(max_read);

        // Process data in the buffer.
        switch (m_recv_state) {
        case RecvState::KEY_MAYBE_V1:
            ProcessReceivedMaybeV1Bytes();
            if (m_recv_state == RecvState::V1) return true;
            break;

        case RecvState::KEY:
            if (!ProcessReceivedKeyBytes()) return false;
            break;

        case RecvState::GARB_GARBTERM:
            if (!ProcessReceivedGarbageBytes()) return false;
            break;

        case RecvState::VERSION:
        case RecvState::APP:
            if (!ProcessReceivedPacketBytes()) return false;
            break;

        case RecvState::APP_READY:
            return true;

        case RecvState::V1:
            // We should have bailed out before.
            Assume(false);
            break;
        }
        // Make sure we have made progress before continuing.
        Assume(max_read > 0);
    }

    return true;
}

std::optional<std::string> V2Transport::GetMessageType(std::span<const uint8_t>& contents) noexcept
{
    if (contents.size() == 0) return std::nullopt; // Empty contents
    uint8_t first_byte = contents[0];
    contents = contents.subspan(1); // Strip first byte.

    if (first_byte != 0) {
        // Short (1 byte) encoding.
        if (first_byte < std::size(V2_MESSAGE_IDS)) {
            // Valid short message id.
            return V2_MESSAGE_IDS[first_byte];
        } else {
            // Unknown short message id.
            return std::nullopt;
        }
    }

    if (contents.size() < CMessageHeader::MESSAGE_TYPE_SIZE) {
        return std::nullopt; // Long encoding needs 12 message type bytes.
    }

    size_t msg_type_len{0};
    while (msg_type_len < CMessageHeader::MESSAGE_TYPE_SIZE && contents[msg_type_len] != 0) {
        // Verify that message type bytes before the first 0x00 are in range.
        if (contents[msg_type_len] < ' ' || contents[msg_type_len] > 0x7F) {
            return {};
        }
        ++msg_type_len;
    }
    std::string ret{reinterpret_cast<const char*>(contents.data()), msg_type_len};
    while (msg_type_len < CMessageHeader::MESSAGE_TYPE_SIZE) {
        // Verify that message type bytes after the first 0x00 are also 0x00.
        if (contents[msg_type_len] != 0) return {};
        ++msg_type_len;
    }
    // Strip message type bytes of contents.
    contents = contents.subspan(CMessageHeader::MESSAGE_TYPE_SIZE);
    return ret;
}

CNetMessage V2Transport::GetReceivedMessage(std::chrono::microseconds time, bool& reject_message) noexcept
{
    AssertLockNotHeld(m_recv_mutex);
    LOCK(m_recv_mutex);
    if (m_recv_state == RecvState::V1) return m_v1_fallback.GetReceivedMessage(time, reject_message);

    Assume(m_recv_state == RecvState::APP_READY);
    std::span<const uint8_t> contents{m_recv_decode_buffer};
    auto msg_type = GetMessageType(contents);
    CNetMessage msg{DataStream{}};
    // Note that BIP324Cipher::EXPANSION also includes the length descriptor size.
    msg.m_raw_message_size = m_recv_decode_buffer.size() + BIP324Cipher::EXPANSION;
    if (msg_type) {
        reject_message = false;
        msg.m_type = std::move(*msg_type);
        msg.m_time = time;
        msg.m_message_size = contents.size();
        msg.m_recv.resize(contents.size());
        std::copy(contents.begin(), contents.end(), UCharCast(msg.m_recv.data()));
    } else {
        LogDebug(BCLog::NET, "V2 transport error: invalid message type (%u bytes contents), peer=%d\n", m_recv_decode_buffer.size(), m_nodeid);
        reject_message = true;
    }
    ClearShrink(m_recv_decode_buffer);
    SetReceiveState(RecvState::APP);

    return msg;
}

bool V2Transport::SetMessageToSend(CSerializedNetMsg& msg) noexcept
{
    AssertLockNotHeld(m_send_mutex);
    LOCK(m_send_mutex);
    if (m_send_state == SendState::V1) return m_v1_fallback.SetMessageToSend(msg);
    // We only allow adding a new message to be sent when in the READY state (so the packet cipher
    // is available) and the send buffer is empty. This limits the number of messages in the send
    // buffer to just one, and leaves the responsibility for queueing them up to the caller.
    if (!(m_send_state == SendState::READY && m_send_buffer.empty())) return false;
    // Construct contents (encoding message type + payload).
    std::vector<uint8_t> contents;
    auto short_message_id = V2_MESSAGE_MAP(msg.m_type);
    if (short_message_id) {
        contents.resize(1 + msg.data.size());
        contents[0] = *short_message_id;
        std::copy(msg.data.begin(), msg.data.end(), contents.begin() + 1);
    } else {
        // Initialize with zeroes, and then write the message type string starting at offset 1.
        // This means contents[0] and the unused positions in contents[1..13] remain 0x00.
        contents.resize(1 + CMessageHeader::MESSAGE_TYPE_SIZE + msg.data.size(), 0);
        std::copy(msg.m_type.begin(), msg.m_type.end(), contents.data() + 1);
        std::copy(msg.data.begin(), msg.data.end(), contents.begin() + 1 + CMessageHeader::MESSAGE_TYPE_SIZE);
    }
    // Construct ciphertext in send buffer.
    m_send_buffer.resize(contents.size() + BIP324Cipher::EXPANSION);
    m_cipher.Encrypt(MakeByteSpan(contents), {}, false, MakeWritableByteSpan(m_send_buffer));
    m_send_type = msg.m_type;
    // Release memory
    ClearShrink(msg.data);
    return true;
}

Transport::BytesToSend V2Transport::GetBytesToSend(bool have_next_message) const noexcept
{
    AssertLockNotHeld(m_send_mutex);
    LOCK(m_send_mutex);
    if (m_send_state == SendState::V1) return m_v1_fallback.GetBytesToSend(have_next_message);

    if (m_send_state == SendState::MAYBE_V1) Assume(m_send_buffer.empty());
    Assume(m_send_pos <= m_send_buffer.size());
    return {
        std::span{m_send_buffer}.subspan(m_send_pos),
        // We only have more to send after the current m_send_buffer if there is a (next)
        // message to be sent, and we're capable of sending packets. */
        have_next_message && m_send_state == SendState::READY,
        m_send_type
    };
}

void V2Transport::MarkBytesSent(size_t bytes_sent) noexcept
{
    AssertLockNotHeld(m_send_mutex);
    LOCK(m_send_mutex);
    if (m_send_state == SendState::V1) return m_v1_fallback.MarkBytesSent(bytes_sent);

    if (m_send_state == SendState::AWAITING_KEY && m_send_pos == 0 && bytes_sent > 0) {
        LogDebug(BCLog::NET, "start sending v2 handshake to peer=%d\n", m_nodeid);
    }

    m_send_pos += bytes_sent;
    Assume(m_send_pos <= m_send_buffer.size());
    if (m_send_pos >= CMessageHeader::HEADER_SIZE) {
        m_sent_v1_header_worth = true;
    }
    // Wipe the buffer when everything is sent.
    if (m_send_pos == m_send_buffer.size()) {
        m_send_pos = 0;
        ClearShrink(m_send_buffer);
    }
}

bool V2Transport::ShouldReconnectV1() const noexcept
{
    AssertLockNotHeld(m_send_mutex);
    AssertLockNotHeld(m_recv_mutex);
    // Only outgoing connections need reconnection.
    if (!m_initiating) return false;

    LOCK(m_recv_mutex);
    // We only reconnect in the very first state and when the receive buffer is empty. Together
    // these conditions imply nothing has been received so far.
    if (m_recv_state != RecvState::KEY) return false;
    if (!m_recv_buffer.empty()) return false;
    // Check if we've sent enough for the other side to disconnect us (if it was V1).
    LOCK(m_send_mutex);
    return m_sent_v1_header_worth;
}

size_t V2Transport::GetSendMemoryUsage() const noexcept
{
    AssertLockNotHeld(m_send_mutex);
    LOCK(m_send_mutex);
    if (m_send_state == SendState::V1) return m_v1_fallback.GetSendMemoryUsage();

    return sizeof(m_send_buffer) + memusage::DynamicUsage(m_send_buffer);
}

Transport::Info V2Transport::GetInfo() const noexcept
{
    AssertLockNotHeld(m_recv_mutex);
    LOCK(m_recv_mutex);
    if (m_recv_state == RecvState::V1) return m_v1_fallback.GetInfo();

    Transport::Info info;

    // Do not report v2 and session ID until the version packet has been received
    // and verified (confirming that the other side very likely has the same keys as us).
    if (m_recv_state != RecvState::KEY_MAYBE_V1 && m_recv_state != RecvState::KEY &&
        m_recv_state != RecvState::GARB_GARBTERM && m_recv_state != RecvState::VERSION) {
        info.transport_type = TransportProtocolType::V2;
        info.session_id = uint256(MakeUCharSpan(m_cipher.GetSessionID()));
    } else {
        info.transport_type = TransportProtocolType::DETECTING;
    }

    return info;
}

std::pair<size_t, bool> CConnman::SocketSendData(CNode& node) const
{
    auto it = node.vSendMsg.begin();
    size_t nSentSize = 0;
    bool data_left{false}; //!< second return value (whether unsent data remains)
    std::optional<bool> expected_more;

    while (true) {
        if (it != node.vSendMsg.end()) {
            // If possible, move one message from the send queue to the transport. This fails when
            // there is an existing message still being sent, or (for v2 transports) when the
            // handshake has not yet completed.
            size_t memusage = it->GetMemoryUsage();
            if (node.m_transport->SetMessageToSend(*it)) {
                // Update memory usage of send buffer (as *it will be deleted).
                node.m_send_memusage -= memusage;
                ++it;
            }
        }
        const auto& [data, more, msg_type] = node.m_transport->GetBytesToSend(it != node.vSendMsg.end());
        // We rely on the 'more' value returned by GetBytesToSend to correctly predict whether more
        // bytes are still to be sent, to correctly set the MSG_MORE flag. As a sanity check,
        // verify that the previously returned 'more' was correct.
        if (expected_more.has_value()) Assume(!data.empty() == *expected_more);
        expected_more = more;
        data_left = !data.empty(); // will be overwritten on next loop if all of data gets sent
        int nBytes = 0;
        if (!data.empty()) {
            LOCK(node.m_sock_mutex);
            // There is no socket in case we've already disconnected, or in test cases without
            // real connections. In these cases, we bail out immediately and just leave things
            // in the send queue and transport.
            if (!node.m_sock) {
                break;
            }
            int flags = MSG_NOSIGNAL | MSG_DONTWAIT;
#ifdef MSG_MORE
            if (more) {
                flags |= MSG_MORE;
            }
#endif
            nBytes = node.m_sock->Send(data.data(), data.size(), flags);
        }
        if (nBytes > 0) {
            node.m_last_send = GetTime<std::chrono::seconds>();
            node.nSendBytes += nBytes;
            // Notify transport that bytes have been processed.
            node.m_transport->MarkBytesSent(nBytes);
            // Update statistics per message type.
            if (!msg_type.empty()) { // don't report v2 handshake bytes for now
                node.AccountForSentBytes(msg_type, nBytes);
            }
            nSentSize += nBytes;
            if ((size_t)nBytes != data.size()) {
                // could not send full message; stop sending more
                break;
            }
        } else {
            if (nBytes < 0) {
                // error
                int nErr = WSAGetLastError();
                if (nErr != WSAEWOULDBLOCK && nErr != WSAEMSGSIZE && nErr != WSAEINTR && nErr != WSAEINPROGRESS) {
                    LogDebug(BCLog::NET, "socket send error, %s: %s", node.DisconnectMsg(), NetworkErrorString(nErr));
                    node.CloseSocketDisconnect();
                }
            }
            break;
        }
    }

    node.fPauseSend = node.m_send_memusage + node.m_transport->GetSendMemoryUsage() > nSendBufferMaxSize;

    if (it == node.vSendMsg.end()) {
        assert(node.m_send_memusage == 0);
    }
    node.vSendMsg.erase(node.vSendMsg.begin(), it);
    return {nSentSize, data_left};
}

/** Try to find a connection to evict when the node is full.
 *  Extreme care must be taken to avoid opening the node to attacker
 *   triggered network partitioning.
 *  The strategy used here is to protect a small number of peers
 *   for each of several distinct characteristics which are difficult
 *   to forge.  In order to partition a node the attacker must be
 *   simultaneously better at all of them than honest peers.
 */
bool CConnman::AttemptToEvictConnection()
{
    std::vector<NodeEvictionCandidate> vEvictionCandidates;
    {

        LOCK(m_nodes_mutex);
        for (const CNode* node : m_nodes) {
            if (node->fDisconnect)
                continue;
            NodeEvictionCandidate candidate{
                .id = node->GetId(),
                .m_connected = node->m_connected,
                .m_min_ping_time = node->m_min_ping_time,
                .m_last_block_time = node->m_last_block_time,
                .m_last_tx_time = node->m_last_tx_time,
                .fRelevantServices = node->m_has_all_wanted_services,
                .m_relay_txs = node->m_relays_txs.load(),
                .fBloomFilter = node->m_bloom_filter_loaded.load(),
                .nKeyedNetGroup = node->nKeyedNetGroup,
                .prefer_evict = node->m_prefer_evict,
                .m_is_local = node->addr.IsLocal(),
                .m_network = node->ConnectedThroughNetwork(),
                .m_noban = node->HasPermission(NetPermissionFlags::NoBan),
                .m_conn_type = node->m_conn_type,
            };
            vEvictionCandidates.push_back(candidate);
        }
    }
    const std::optional<NodeId> node_id_to_evict = SelectNodeToEvict(std::move(vEvictionCandidates));
    if (!node_id_to_evict) {
        return false;
    }
    LOCK(m_nodes_mutex);
    for (CNode* pnode : m_nodes) {
        if (pnode->GetId() == *node_id_to_evict) {
            LogDebug(BCLog::NET, "selected %s connection for eviction, %s", pnode->ConnectionTypeAsString(), pnode->DisconnectMsg());
            TRACEPOINT(net, evicted_inbound_connection,
                pnode->GetId(),
                pnode->m_addr_name.c_str(),
                pnode->ConnectionTypeAsString().c_str(),
                pnode->ConnectedThroughNetwork(),
                Ticks<std::chrono::seconds>(pnode->m_connected));
            pnode->fDisconnect = true;
            return true;
        }
    }
    return false;
}

void CConnman::AcceptConnection(const ListenSocket& hListenSocket) {
    struct sockaddr_storage sockaddr;
    socklen_t len = sizeof(sockaddr);
    auto sock = hListenSocket.sock->Accept((struct sockaddr*)&sockaddr, &len);

    if (!sock) {
        const int nErr = WSAGetLastError();
        if (nErr != WSAEWOULDBLOCK) {
            LogInfo("socket error accept failed: %s\n", NetworkErrorString(nErr));
        }
        return;
    }

    CService addr;
    if (!addr.SetSockAddr((const struct sockaddr*)&sockaddr, len)) {
        LogWarning("Unknown socket family\n");
    } else {
        addr = MaybeFlipIPv6toCJDNS(addr);
    }

    const CService addr_bind{MaybeFlipIPv6toCJDNS(GetBindAddress(*sock))};

    NetPermissionFlags permission_flags = NetPermissionFlags::None;
    hListenSocket.AddSocketPermissionFlags(permission_flags);

    CreateNodeFromAcceptedSocket(std::move(sock), permission_flags, addr_bind, addr);
}

void CConnman::CreateNodeFromAcceptedSocket(std::unique_ptr<Sock>&& sock,
                                            NetPermissionFlags permission_flags,
                                            const CService& addr_bind,
                                            const CService& addr)
{
    int nInbound = 0;

    const bool inbound_onion = std::find(m_onion_binds.begin(), m_onion_binds.end(), addr_bind) != m_onion_binds.end();

    // Tor inbound connections do not reveal the peer's actual network address.
    // Therefore do not apply address-based whitelist permissions to them.
    AddWhitelistPermissionFlags(permission_flags, inbound_onion ? std::optional<CNetAddr>{} : addr, vWhitelistedRangeIncoming);

    {
        LOCK(m_nodes_mutex);
        for (const CNode* pnode : m_nodes) {
            if (pnode->IsInboundConn()) nInbound++;
        }
    }

    if (!fNetworkActive) {
        LogDebug(BCLog::NET, "connection from %s dropped: not accepting new connections\n", addr.ToStringAddrPort());
        return;
    }

    if (!sock->IsSelectable()) {
        LogInfo("connection from %s dropped: non-selectable socket\n", addr.ToStringAddrPort());
        return;
    }

    // According to the internet TCP_NODELAY is not carried into accepted sockets
    // on all platforms.  Set it again here just to be sure.
    const int on{1};
    if (sock->SetSockOpt(IPPROTO_TCP, TCP_NODELAY, &on, sizeof(on)) == SOCKET_ERROR) {
        LogDebug(BCLog::NET, "connection from %s: unable to set TCP_NODELAY, continuing anyway\n",
                 addr.ToStringAddrPort());
    }

    // Don't accept connections from banned peers.
    bool banned = m_banman && m_banman->IsBanned(addr);
    if (!NetPermissions::HasFlag(permission_flags, NetPermissionFlags::NoBan) && banned)
    {
        LogDebug(BCLog::NET, "connection from %s dropped (banned)\n", addr.ToStringAddrPort());
        return;
    }

    // Only accept connections from discouraged peers if our inbound slots aren't (almost) full.
    bool discouraged = m_banman && m_banman->IsDiscouraged(addr);
    if (!NetPermissions::HasFlag(permission_flags, NetPermissionFlags::NoBan) && nInbound + 1 >= m_max_inbound && discouraged)
    {
        LogDebug(BCLog::NET, "connection from %s dropped (discouraged)\n", addr.ToStringAddrPort());
        return;
    }

    if (nInbound >= m_max_inbound)
    {
        if (!AttemptToEvictConnection()) {
            // No connection to evict, disconnect the new connection
            LogDebug(BCLog::NET, "failed to find an eviction candidate - connection dropped (full)\n");
            return;
        }
    }

    NodeId id = GetNewNodeId();
    uint64_t nonce = GetDeterministicRandomizer(RANDOMIZER_ID_LOCALHOSTNONCE).Write(id).Finalize();

    // The V2Transport transparently falls back to V1 behavior when an incoming V1 connection is
    // detected, so use it whenever we signal NODE_P2P_V2.
    ServiceFlags local_services = GetLocalServices();
    const bool use_v2transport(local_services & NODE_P2P_V2);

    uint64_t network_id = GetDeterministicRandomizer(RANDOMIZER_ID_NETWORKKEY)
                        .Write(inbound_onion ? NET_ONION : addr.GetNetClass())
                        .Write(addr_bind.GetAddrBytes())
                        .Write(addr_bind.GetPort()) // inbound connections use bind port
                        .Finalize();
    CNode* pnode = new CNode(id,
                             std::move(sock),
                             CAddress{addr, NODE_NONE},
                             CalculateKeyedNetGroup(addr),
                             nonce,
                             addr_bind,
                             /*addrNameIn=*/"",
                             ConnectionType::INBOUND,
                             inbound_onion,
                             network_id,
                             CNodeOptions{
                                 .permission_flags = permission_flags,
                                 .prefer_evict = discouraged,
                                 .recv_flood_size = nReceiveFloodSize,
                                 .use_v2transport = use_v2transport,
                             });
    pnode->AddRef();
    m_msgproc->InitializeNode(*pnode, local_services);
    {
        LOCK(m_nodes_mutex);
        m_nodes.push_back(pnode);
    }
    LogDebug(BCLog::NET, "connection from %s accepted\n", addr.ToStringAddrPort());
    TRACEPOINT(net, inbound_connection,
        pnode->GetId(),
        pnode->m_addr_name.c_str(),
        pnode->ConnectionTypeAsString().c_str(),
        pnode->ConnectedThroughNetwork(),
        GetNodeCount(ConnectionDirection::In));

    // We received a new connection, harvest entropy from the time (and our peer count)
    RandAddEvent((uint32_t)id);
}

bool CConnman::AddConnection(const std::string& address, ConnectionType conn_type, bool use_v2transport = false)
{
    AssertLockNotHeld(m_unused_i2p_sessions_mutex);
    std::optional<int> max_connections;
    switch (conn_type) {
    case ConnectionType::INBOUND:
    case ConnectionType::MANUAL:
    case ConnectionType::PRIVATE_BROADCAST:
        return false;
    case ConnectionType::OUTBOUND_FULL_RELAY:
        max_connections = m_max_outbound_full_relay;
        break;
    case ConnectionType::BLOCK_RELAY:
        max_connections = m_max_outbound_block_relay;
        break;
    // no limit for ADDR_FETCH because -seednode has no limit either
    case ConnectionType::ADDR_FETCH:
        break;
    // no limit for FEELER connections since they're short-lived
    case ConnectionType::FEELER:
        break;
    } // no default case, so the compiler can warn about missing cases

    // Count existing connections
    int existing_connections = WITH_LOCK(m_nodes_mutex,
                                         return std::count_if(m_nodes.begin(), m_nodes.end(), [conn_type](CNode* node) { return node->m_conn_type == conn_type; }););

    // Max connections of specified type already exist
    if (max_connections != std::nullopt && existing_connections >= max_connections) return false;

    // Max total outbound connections already exist
    CountingSemaphoreGrant<> grant(*semOutbound, true);
    if (!grant) return false;

    OpenNetworkConnection(CAddress(), false, std::move(grant), address.c_str(), conn_type, /*use_v2transport=*/use_v2transport);
    return true;
}

void CConnman::DisconnectNodes()
{
    AssertLockNotHeld(m_nodes_mutex);
    AssertLockNotHeld(m_reconnections_mutex);

    // Use a temporary variable to accumulate desired reconnections, so we don't need
    // m_reconnections_mutex while holding m_nodes_mutex.
    decltype(m_reconnections) reconnections_to_add;

    {
        LOCK(m_nodes_mutex);

        const bool network_active{fNetworkActive};
        if (!network_active) {
            // Disconnect any connected nodes
            for (CNode* pnode : m_nodes) {
                if (!pnode->fDisconnect) {
                    LogDebug(BCLog::NET, "Network not active, %s", pnode->DisconnectMsg());
                    pnode->fDisconnect = true;
                }
            }
        }

        // Disconnect unused nodes
        std::vector<CNode*> nodes_copy = m_nodes;
        for (CNode* pnode : nodes_copy)
        {
            if (pnode->fDisconnect)
            {
                // remove from m_nodes
                m_nodes.erase(remove(m_nodes.begin(), m_nodes.end(), pnode), m_nodes.end());

                // Add to reconnection list if appropriate. We don't reconnect right here, because
                // the creation of a connection is a blocking operation (up to several seconds),
                // and we don't want to hold up the socket handler thread for that long.
                if (network_active && pnode->m_transport->ShouldReconnectV1()) {
                    reconnections_to_add.push_back({
                        .addr_connect = pnode->addr,
                        .grant = std::move(pnode->grantOutbound),
                        .destination = pnode->m_dest,
                        .conn_type = pnode->m_conn_type,
                        .use_v2transport = false});
                    LogDebug(BCLog::NET, "retrying with v1 transport protocol for peer=%d\n", pnode->GetId());
                }

                // release outbound grant (if any)
                pnode->grantOutbound.Release();

                // close socket and cleanup
                pnode->CloseSocketDisconnect();

                // update connection count by network
                if (pnode->IsManualOrFullOutboundConn()) --m_network_conn_counts[pnode->addr.GetNetwork()];

                // hold in disconnected pool until all refs are released
                pnode->Release();
                m_nodes_disconnected.push_back(pnode);
            }
        }
    }
    {
        // Delete disconnected nodes
        std::list<CNode*> nodes_disconnected_copy = m_nodes_disconnected;
        for (CNode* pnode : nodes_disconnected_copy)
        {
            // Destroy the object only after other threads have stopped using it.
            if (pnode->GetRefCount() <= 0) {
                m_nodes_disconnected.remove(pnode);
                DeleteNode(pnode);
            }
        }
    }
    {
        // Move entries from reconnections_to_add to m_reconnections.
        LOCK(m_reconnections_mutex);
        m_reconnections.splice(m_reconnections.end(), std::move(reconnections_to_add));
    }
}

void CConnman::NotifyNumConnectionsChanged()
{
    size_t nodes_size;
    {
        LOCK(m_nodes_mutex);
        nodes_size = m_nodes.size();
    }
    if(nodes_size != nPrevNodeCount) {
        nPrevNodeCount = nodes_size;
        if (m_client_interface) {
            m_client_interface->NotifyNumConnectionsChanged(nodes_size);
        }
    }
}

bool CConnman::ShouldRunInactivityChecks(const CNode& node, std::chrono::microseconds now) const
{
    return node.m_connected + m_peer_connect_timeout < now;
}

bool CConnman::InactivityCheck(const CNode& node, std::chrono::microseconds now) const
{
    // Tests that see disconnects after using mocktime can start nodes with a
    // large timeout. For example, -peertimeout=999999999.
    const auto last_send{node.m_last_send.load()};
    const auto last_recv{node.m_last_recv.load()};

    if (!ShouldRunInactivityChecks(node, now)) return false;

    bool has_received{last_recv.count() != 0};
    bool has_sent{last_send.count() != 0};

    if (!has_received || !has_sent) {
        std::string has_never;
        if (!has_received) has_never += ", never received from peer";
        if (!has_sent) has_never += ", never sent to peer";
        LogDebug(BCLog::NET,
            "socket no message in first %i seconds%s, %s",
            count_seconds(m_peer_connect_timeout),
            has_never,
            node.DisconnectMsg()
        );
        return true;
    }

    if (now > last_send + TIMEOUT_INTERVAL) {
        LogDebug(BCLog::NET,
            "socket sending timeout: %is, %s", Ticks<std::chrono::seconds>(now - last_send),
            node.DisconnectMsg()
        );
        return true;
    }

    if (now > last_recv + TIMEOUT_INTERVAL) {
        LogDebug(BCLog::NET,
            "socket receive timeout: %is, %s", Ticks<std::chrono::seconds>(now - last_recv),
            node.DisconnectMsg()
        );
        return true;
    }

    if (!node.fSuccessfullyConnected) {
        if (node.m_transport->GetInfo().transport_type == TransportProtocolType::DETECTING) {
            LogDebug(BCLog::NET, "V2 handshake timeout, %s", node.DisconnectMsg());
        } else {
            LogDebug(BCLog::NET, "version handshake timeout, %s", node.DisconnectMsg());
        }
        return true;
    }

    return false;
}

Sock::EventsPerSock CConnman::GenerateWaitSockets(std::span<CNode* const> nodes)
{
    Sock::EventsPerSock events_per_sock;

    for (const ListenSocket& hListenSocket : vhListenSocket) {
        events_per_sock.emplace(hListenSocket.sock, Sock::Events{Sock::RECV});
    }

    for (CNode* pnode : nodes) {
        bool select_recv = !pnode->fPauseRecv;
        bool select_send;
        {
            LOCK(pnode->cs_vSend);
            // Sending is possible if either there are bytes to send right now, or if there will be
            // once a potential message from vSendMsg is handed to the transport. GetBytesToSend
            // determines both of these in a single call.
            const auto& [to_send, more, _msg_type] = pnode->m_transport->GetBytesToSend(!pnode->vSendMsg.empty());
            select_send = !to_send.empty() || more;
        }
        if (!select_recv && !select_send) continue;

        LOCK(pnode->m_sock_mutex);
        if (pnode->m_sock) {
            Sock::Event event = (select_send ? Sock::SEND : 0) | (select_recv ? Sock::RECV : 0);
            events_per_sock.emplace(pnode->m_sock, Sock::Events{event});
        }
    }

    return events_per_sock;
}

void CConnman::SocketHandler()
{
    AssertLockNotHeld(m_total_bytes_sent_mutex);

    Sock::EventsPerSock events_per_sock;

    {
        const NodesSnapshot snap{*this, /*shuffle=*/false};

        const auto timeout = std::chrono::milliseconds(SELECT_TIMEOUT_MILLISECONDS);

        // Check for the readiness of the already connected sockets and the
        // listening sockets in one call ("readiness" as in poll(2) or
        // select(2)). If none are ready, wait for a short while and return
        // empty sets.
        events_per_sock = GenerateWaitSockets(snap.Nodes());
        if (events_per_sock.empty() || !events_per_sock.begin()->first->WaitMany(timeout, events_per_sock)) {
            m_interrupt_net->sleep_for(timeout);
        }

        // Service (send/receive) each of the already connected nodes.
        SocketHandlerConnected(snap.Nodes(), events_per_sock);
    }

    // Accept new connections from listening sockets.
    SocketHandlerListening(events_per_sock);
}

void CConnman::SocketHandlerConnected(const std::vector<CNode*>& nodes,
                                      const Sock::EventsPerSock& events_per_sock)
{
    AssertLockNotHeld(m_total_bytes_sent_mutex);

    auto now = GetTime<std::chrono::microseconds>();

    for (CNode* pnode : nodes) {
        if (m_interrupt_net->interrupted()) {
            return;
        }

        //
        // Receive
        //
        bool recvSet = false;
        bool sendSet = false;
        bool errorSet = false;
        {
            LOCK(pnode->m_sock_mutex);
            if (!pnode->m_sock) {
                continue;
            }
            const auto it = events_per_sock.find(pnode->m_sock);
            if (it != events_per_sock.end()) {
                recvSet = it->second.occurred & Sock::RECV;
                sendSet = it->second.occurred & Sock::SEND;
                errorSet = it->second.occurred & Sock::ERR;
            }
        }

        if (sendSet) {
            // Send data
            auto [bytes_sent, data_left] = WITH_LOCK(pnode->cs_vSend, return SocketSendData(*pnode));
            if (bytes_sent) {
                RecordBytesSent(bytes_sent);

                // If both receiving and (non-optimistic) sending were possible, we first attempt
                // sending. If that succeeds, but does not fully drain the send queue, do not
                // attempt to receive. This avoids needlessly queueing data if the remote peer
                // is slow at receiving data, by means of TCP flow control. We only do this when
                // sending actually succeeded to make sure progress is always made; otherwise a
                // deadlock would be possible when both sides have data to send, but neither is
                // receiving.
                if (data_left) recvSet = false;
            }
        }

        if (recvSet || errorSet)
        {
            // typical socket buffer is 8K-64K
            uint8_t pchBuf[0x10000];
            int nBytes = 0;
            {
                LOCK(pnode->m_sock_mutex);
                if (!pnode->m_sock) {
                    continue;
                }
                nBytes = pnode->m_sock->Recv(pchBuf, sizeof(pchBuf), MSG_DONTWAIT);
            }
            if (nBytes > 0)
            {
                bool notify = false;
                if (!pnode->ReceiveMsgBytes({pchBuf, (size_t)nBytes}, notify)) {
                    LogDebug(BCLog::NET,
                        "receiving message bytes failed, %s",
                        pnode->DisconnectMsg()
                    );
                    pnode->CloseSocketDisconnect();
                }
                RecordBytesRecv(nBytes);
                if (notify) {
                    pnode->MarkReceivedMsgsForProcessing();
                    WakeMessageHandler();
                }
            }
            else if (nBytes == 0)
            {
                // socket closed gracefully
                if (!pnode->fDisconnect) {
                    LogDebug(BCLog::NET, "socket closed, %s", pnode->DisconnectMsg());
                }
                pnode->CloseSocketDisconnect();
            }
            else if (nBytes < 0)
            {
                // error
                int nErr = WSAGetLastError();
                if (nErr != WSAEWOULDBLOCK && nErr != WSAEMSGSIZE && nErr != WSAEINTR && nErr != WSAEINPROGRESS)
                {
                    if (!pnode->fDisconnect) {
                        LogDebug(BCLog::NET, "socket recv error, %s: %s", pnode->DisconnectMsg(), NetworkErrorString(nErr));
                    }
                    pnode->CloseSocketDisconnect();
                }
            }
        }

        if (InactivityCheck(*pnode, now)) pnode->fDisconnect = true;
    }
}

void CConnman::SocketHandlerListening(const Sock::EventsPerSock& events_per_sock)
{
    for (const ListenSocket& listen_socket : vhListenSocket) {
        if (m_interrupt_net->interrupted()) {
            return;
        }
        const auto it = events_per_sock.find(listen_socket.sock);
        if (it != events_per_sock.end() && it->second.occurred & Sock::RECV) {
            AcceptConnection(listen_socket);
        }
    }
}

void CConnman::ThreadSocketHandler()
{
    AssertLockNotHeld(m_total_bytes_sent_mutex);

    while (!m_interrupt_net->interrupted()) {
        DisconnectNodes();
        NotifyNumConnectionsChanged();
        SocketHandler();
    }
}

void CConnman::WakeMessageHandler()
{
    {
        LOCK(mutexMsgProc);
        fMsgProcWake = true;
    }
    condMsgProc.notify_one();
}

void CConnman::ThreadDNSAddressSeed()
{
    int outbound_connection_count = 0;

    if (!gArgs.GetArgs("-seednode").empty()) {
        auto start = NodeClock::now();
        constexpr std::chrono::seconds SEEDNODE_TIMEOUT = 30s;
        LogInfo("-seednode enabled. Trying the provided seeds for %d seconds before defaulting to the dnsseeds.\n", SEEDNODE_TIMEOUT.count());
        while (!m_interrupt_net->interrupted()) {
            if (!m_interrupt_net->sleep_for(500ms)) {
                return;
            }

            // Abort if we have spent enough time without reaching our target.
            // Giving seed nodes 30 seconds so this does not become a race against fixedseeds (which triggers after 1 min)
            if (NodeClock::now() > start + SEEDNODE_TIMEOUT) {
                LogInfo("Couldn't connect to enough peers via seed nodes. Handing fetch logic to the DNS seeds.\n");
                break;
            }

            outbound_connection_count = GetFullOutboundConnCount();
            if (outbound_connection_count >= SEED_OUTBOUND_CONNECTION_THRESHOLD) {
                LogInfo("P2P peers available. Finished fetching data from seed nodes.\n");
                break;
            }
        }
    }

    FastRandomContext rng;
    std::vector<std::string> seeds = m_params.DNSSeeds();
    std::shuffle(seeds.begin(), seeds.end(), rng);
    int seeds_right_now = 0; // Number of seeds left before testing if we have enough connections

    if (gArgs.GetBoolArg("-forcednsseed", DEFAULT_FORCEDNSSEED)) {
        // When -forcednsseed is provided, query all.
        seeds_right_now = seeds.size();
    } else if (addrman.get().Size() == 0) {
        // If we have no known peers, query all.
        // This will occur on the first run, or if peers.dat has been
        // deleted.
        seeds_right_now = seeds.size();
    }

    // Proceed with dnsseeds if seednodes hasn't reached the target or if forcednsseed is set
    if (outbound_connection_count < SEED_OUTBOUND_CONNECTION_THRESHOLD || seeds_right_now) {
        // goal: only query DNS seed if address need is acute
        // * If we have a reasonable number of peers in addrman, spend
        //   some time trying them first. This improves user privacy by
        //   creating fewer identifying DNS requests, reduces trust by
        //   giving seeds less influence on the network topology, and
        //   reduces traffic to the seeds.
        // * When querying DNS seeds query a few at once, this ensures
        //   that we don't give DNS seeds the ability to eclipse nodes
        //   that query them.
        // * If we continue having problems, eventually query all the
        //   DNS seeds, and if that fails too, also try the fixed seeds.
        //   (done in ThreadOpenConnections)
        int found = 0;
        const std::chrono::seconds seeds_wait_time = (addrman.get().Size() >= DNSSEEDS_DELAY_PEER_THRESHOLD ? DNSSEEDS_DELAY_MANY_PEERS : DNSSEEDS_DELAY_FEW_PEERS);

        for (const std::string& seed : seeds) {
            if (seeds_right_now == 0) {
                seeds_right_now += DNSSEEDS_TO_QUERY_AT_ONCE;

                if (addrman.get().Size() > 0) {
                    LogInfo("Waiting %d seconds before querying DNS seeds.\n", seeds_wait_time.count());
                    std::chrono::seconds to_wait = seeds_wait_time;
                    while (to_wait.count() > 0) {
                        // if sleeping for the MANY_PEERS interval, wake up
                        // early to see if we have enough peers and can stop
                        // this thread entirely freeing up its resources
                        std::chrono::seconds w = std::min(DNSSEEDS_DELAY_FEW_PEERS, to_wait);
                        if (!m_interrupt_net->sleep_for(w)) return;
                        to_wait -= w;

                        if (GetFullOutboundConnCount() >= SEED_OUTBOUND_CONNECTION_THRESHOLD) {
                            if (found > 0) {
                                LogInfo("%d addresses found from DNS seeds\n", found);
                                LogInfo("P2P peers available. Finished DNS seeding.\n");
                            } else {
                                LogInfo("P2P peers available. Skipped DNS seeding.\n");
                            }
                            return;
                        }
                    }
                }
            }

            if (m_interrupt_net->interrupted()) return;

            // hold off on querying seeds if P2P network deactivated
            if (!fNetworkActive) {
                LogInfo("Waiting for network to be reactivated before querying DNS seeds.\n");
                do {
                    if (!m_interrupt_net->sleep_for(1s)) return;
                } while (!fNetworkActive);
            }

            LogInfo("Loading addresses from DNS seed %s\n", seed);
            // If -proxy is in use, we make an ADDR_FETCH connection to the DNS resolved peer address
            // for the base dns seed domain in chainparams
            if (HaveNameProxy()) {
                AddAddrFetch(seed);
            } else {
                std::vector<CAddress> vAdd;
                constexpr ServiceFlags requiredServiceBits{SeedsServiceFlags()};
                std::string host = strprintf("x%x.%s", requiredServiceBits, seed);
                CNetAddr resolveSource;
                if (!resolveSource.SetInternal(host)) {
                    continue;
                }
                // Limit number of IPs learned from a single DNS seed. This limit exists to prevent the results from
                // one DNS seed from dominating AddrMan. Note that the number of results from a UDP DNS query is
                // bounded to 33 already, but it is possible for it to use TCP where a larger number of results can be
                // returned.
                unsigned int nMaxIPs = 32;
                const auto addresses{LookupHost(host, nMaxIPs, true)};
                if (!addresses.empty()) {
                    for (const CNetAddr& ip : addresses) {
                        CAddress addr = CAddress(CService(ip, m_params.GetDefaultPort()), requiredServiceBits);
                        addr.nTime = rng.rand_uniform_delay(Now<NodeSeconds>() - 3 * 24h, -4 * 24h); // use a random age between 3 and 7 days old
                        vAdd.push_back(addr);
                        found++;
                    }
                    addrman.get().Add(vAdd, resolveSource);
                } else {
                    // If the seed does not support a subdomain with our desired service bits,
                    // we make an ADDR_FETCH connection to the DNS resolved peer address for the
                    // base dns seed domain in chainparams
                    AddAddrFetch(seed);
                }
            }
            --seeds_right_now;
        }
        LogInfo("%d addresses found from DNS seeds\n", found);
    } else {
        LogInfo("Skipping DNS seeds. Enough peers have been found\n");
    }
}

void CConnman::DumpAddresses()
{
    const auto start{SteadyClock::now()};

    DumpPeerAddresses(::gArgs, addrman);

    LogDebug(BCLog::NET, "Flushed %d addresses to peers.dat %dms",
             addrman.get().Size(), Ticks<std::chrono::milliseconds>(SteadyClock::now() - start));
}

void CConnman::ProcessAddrFetch()
{
    AssertLockNotHeld(m_unused_i2p_sessions_mutex);
    std::string strDest;
    {
        LOCK(m_addr_fetches_mutex);
        if (m_addr_fetches.empty())
            return;
        strDest = m_addr_fetches.front();
        m_addr_fetches.pop_front();
    }
    // Attempt v2 connection if we support v2 - we'll reconnect with v1 if our
    // peer doesn't support it or immediately disconnects us for another reason.
    const bool use_v2transport(GetLocalServices() & NODE_P2P_V2);
    CAddress addr;
    CountingSemaphoreGrant<> grant(*semOutbound, /*fTry=*/true);
    if (grant) {
        OpenNetworkConnection(addr, false, std::move(grant), strDest.c_str(), ConnectionType::ADDR_FETCH, use_v2transport);
    }
}

bool CConnman::GetTryNewOutboundPeer() const
{
    return m_try_another_outbound_peer;
}

void CConnman::SetTryNewOutboundPeer(bool flag)
{
    m_try_another_outbound_peer = flag;
    LogDebug(BCLog::NET, "setting try another outbound peer=%s\n", flag ? "true" : "false");
}

void CConnman::StartExtraBlockRelayPeers()
{
    LogDebug(BCLog::NET, "enabling extra block-relay-only peers\n");
    m_start_extra_block_relay_peers = true;
}

// Return the number of outbound connections that are full relay (not blocks only)
int CConnman::GetFullOutboundConnCount() const
{
    int nRelevant = 0;
    {
        LOCK(m_nodes_mutex);
        for (const CNode* pnode : m_nodes) {
            if (pnode->fSuccessfullyConnected && pnode->IsFullOutboundConn()) ++nRelevant;
        }
    }
    return nRelevant;
}

// Return the number of peers we have over our outbound connection limit
// Exclude peers that are marked for disconnect, or are going to be
// disconnected soon (eg ADDR_FETCH and FEELER)
// Also exclude peers that haven't finished initial connection handshake yet
// (so that we don't decide we're over our desired connection limit, and then
// evict some peer that has finished the handshake)
int CConnman::GetExtraFullOutboundCount() const
{
    int full_outbound_peers = 0;
    {
        LOCK(m_nodes_mutex);
        for (const CNode* pnode : m_nodes) {
            if (pnode->fSuccessfullyConnected && !pnode->fDisconnect && pnode->IsFullOutboundConn()) {
                ++full_outbound_peers;
            }
        }
    }
    return std::max(full_outbound_peers - m_max_outbound_full_relay, 0);
}

int CConnman::GetExtraBlockRelayCount() const
{
    int block_relay_peers = 0;
    {
        LOCK(m_nodes_mutex);
        for (const CNode* pnode : m_nodes) {
            if (pnode->fSuccessfullyConnected && !pnode->fDisconnect && pnode->IsBlockOnlyConn()) {
                ++block_relay_peers;
            }
        }
    }
    return std::max(block_relay_peers - m_max_outbound_block_relay, 0);
}

std::unordered_set<Network> CConnman::GetReachableEmptyNetworks() const
{
    std::unordered_set<Network> networks{};
    for (int n = 0; n < NET_MAX; n++) {
        enum Network net = (enum Network)n;
        if (net == NET_UNROUTABLE || net == NET_INTERNAL) continue;
        if (g_reachable_nets.Contains(net) && addrman.get().Size(net, std::nullopt) == 0) {
            networks.insert(net);
        }
    }
    return networks;
}

bool CConnman::MultipleManualOrFullOutboundConns(Network net) const
{
    AssertLockHeld(m_nodes_mutex);
    return m_network_conn_counts[net] > 1;
}

bool CConnman::MaybePickPreferredNetwork(std::optional<Network>& network)
{
    std::array<Network, 5> nets{NET_IPV4, NET_IPV6, NET_ONION, NET_I2P, NET_CJDNS};
    std::shuffle(nets.begin(), nets.end(), FastRandomContext());

    LOCK(m_nodes_mutex);
    for (const auto net : nets) {
        if (g_reachable_nets.Contains(net) && m_network_conn_counts[net] == 0 && addrman.get().Size(net) != 0) {
            network = net;
            return true;
        }
    }

    return false;
}

void CConnman::ThreadOpenConnections(const std::vector<std::string> connect, std::span<const std::string> seed_nodes)
{
    AssertLockNotHeld(m_unused_i2p_sessions_mutex);
    AssertLockNotHeld(m_reconnections_

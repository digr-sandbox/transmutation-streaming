// Copyright (c) 2009-2010 Satoshi Nakamoto
// Copyright (c) 2009-present The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#ifndef BITCOIN_POLICY_FEERATE_H
#define BITCOIN_POLICY_FEERATE_H

#include <consensus/amount.h>
#include <serialize.h>
#include <util/feefrac.h>
#include <util/fees.h>


#include <cstdint>
#include <string>
#include <type_traits>

const std::string CURRENCY_UNIT = "BTC"; // One formatted unit
const std::string CURRENCY_ATOM = "sat"; // One indivisible minimum value unit

enum class FeeRateFormat {
    BTC_KVB, //!< Use BTC/kvB fee rate unit
    SAT_VB,  //!< Use sat/vB fee rate unit
};

/**
 * Fee rate in satoshis per virtualbyte: CAmount / vB
 * the feerate is represented internally as FeeFrac
 */
class CFeeRate
{
private:
    /** Fee rate in sats/vB (satoshis per N virtualbytes) */
    FeePerVSize m_feerate;

public:
    /** Fee rate of 0 satosh

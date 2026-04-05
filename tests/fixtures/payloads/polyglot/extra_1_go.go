/*
Copyright 2015 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package kubelet

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"math"
	"net"
	"net/http"
	"os"
	"path/filepath"
	sysruntime "runtime"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	cadvisorapi "github.com/google/cadvisor/info/v1"
	inuserns "github.com/moby/sys/userns"
	"github.com/opencontainers/selinux/go-selinux"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	semconv "go.opentelemetry.io/otel/semconv/v1.12.0"
	"go.opentelemetry.io/otel/trace"

	"k8s.io/client-go/informers"
	ndf "k8s.io/component-helpers/nodedeclaredfeatures"
	"k8s.io/mount-utils"

	apiequality "k8s.io/apimachinery/pkg/api/equality"
	v1qos "k8s.io/kubernetes/pkg/apis/core/v1/helper/qos"
	"k8s.io/kubernetes/pkg/scheduler/framework/plugins/tainttoleration"
	utilfs "k8s.io/kubernetes/pkg/util/filesystem"
	utilpod "k8s.io/kubernetes/pkg/util/pod"
	netutils "k8s.io/utils/net"
	"k8s.io/utils/ptr"

	v1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/fields"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/types"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	"k8s.io/apimachinery/pkg/util/sets"
	versionutil "k8s.io/apimachinery/pkg/util/version"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/apiserver/pkg/server/dynamiccertificates"
	"k8s.io/apiserver/pkg/server/flagz"
	utilfeature "k8s.io/apiserver/pkg/util/feature"
	coreinformersv1 "k8s.io/client-go/informers/core/v1"
	clientset "k8s.io/client-go/kubernetes"
	v1core "k8s.io/client-go/kubernetes/typed/core/v1"
	corelisters "k8s.io/client-go/listers/core/v1"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/tools/record"
	certutil "k8s.io/client-go/util/cert"
	"k8s.io/client-go/util/certificate"
	"k8s.io/client-go/util/flowcontrol"
	cloudprovider "k8s.io/cloud-provider"
	"k8s.io/component-base/version"
	"k8s.io/component-helpers/apimachinery/lease"
	resourcehelper "k8s.io/component-helpers/resource"
	internalapi "k8s.io/cri-api/pkg/apis"
	runtimeapi "k8s.io/cri-api/pkg/apis/runtime/v1"
	remote "k8s.io/cri-client/pkg"
	"k8s.io/klog/v2"
	pluginwatcherapi "k8s.io/kubelet/pkg/apis/pluginregistration/v1"
	statsapi "k8s.io/kubelet/pkg/apis/stats/v1alpha1"
	podutil "k8s.io/kubernetes/pkg/api/v1/pod"
	"k8s.io/kubernetes/pkg/features"
	"k8s.io/kubernetes/pkg/kubelet/allocation"
	kubeletconfiginternal "k8s.io/kubernetes/pkg/kubelet/apis/config"
	"k8s.io/kubernetes/pkg/kubelet/apis/config/v1beta1"
	"k8s.io/kubernetes/pkg/kubelet/apis/podresources"
	"k8s.io/kubernetes/pkg/kubelet/apis/pods"
	"k8s.io/kubernetes/pkg/kubelet/cadvisor"
	kubeletcertificate "k8s.io/kubernetes/pkg/kubelet/certificate"
	"k8s.io/kubernetes/pkg/kubelet/clustertrustbundle"
	"k8s.io/kubernetes/pkg/kubelet/cm"
	"k8s.io/kubernetes/pkg/kubelet/cm/topologymanager"
	"k8s.io/kubernetes/pkg/kubelet/config"
	"k8s.io/kubernetes/pkg/kubelet/configmap"
	kubecontainer "k8s.io/kubernetes/pkg/kubelet/container"
	"k8s.io/kubernetes/pkg/kubelet/events"
	"k8s.io/kubernetes/pkg/kubelet/eviction"
	"k8s.io/kubernetes/pkg/kubelet/images"
	"k8s.io/kubernetes/pkg/kubelet/kubeletconfig"
	"k8s.io/kubernetes/pkg/kubelet/kuberuntime"
	"k8s.io/kubernetes/pkg/kubelet/lifecycle"
	"k8s.io/kubernetes/pkg/kubelet/logs"
	"k8s.io/kubernetes/pkg/kubelet/metrics"
	"k8s.io/kubernetes/pkg/kubelet/metrics/collectors"
	"k8s.io/kubernetes/pkg/kubelet/network/dns"
	"k8s.io/kubernetes/pkg/kubelet/nodeshutdown"
	oomwatcher "k8s.io/kubernetes/pkg/kubelet/oom"
	"k8s.io/kubernetes/pkg/kubelet/pleg"
	"k8s.io/kubernetes/pkg/kubelet/pluginmanager"
	plugincache "k8s.io/kubernetes/pkg/kubelet/pluginmanager/cache"
	kubepod "k8s.io/kubernetes/pkg/kubelet/pod"
	"k8s.io/kubernetes/pkg/kubelet/podcertificate"
	"k8s.io/kubernetes/pkg/kubelet/preemption"
	"k8s.io/kubernetes/pkg/kubelet/prober"
	proberesults "k8s.io/kubernetes/pkg/kubelet/prober/results"
	"k8s.io/kubernetes/pkg/kubelet/runtimeclass"
	"k8s.io/kubernetes/pkg/kubelet/secret"
	"k8s.io/kubernetes/pkg/kubelet/server"
	servermetrics "k8s.io/kubernetes/pkg/kubelet/server/metrics"
	serverstats "k8s.io/kubernetes/pkg/kubelet/server/stats"
	"k8s.io/kubernetes/pkg/kubelet/stats"
	"k8s.io/kubernetes/pkg/kubelet/status"
	"k8s.io/kubernetes/pkg/kubelet/sysctl"
	"k8s.io/kubernetes/pkg/kubelet/token"
	kubetypes "k8s.io/kubernetes/pkg/kubelet/types"
	"k8s.io/kubernetes/pkg/kubelet/userns"
	"k8s.io/kubernetes/pkg/kubelet/util"
	"k8s.io/kubernetes/pkg/kubelet/util/manager"
	"k8s.io/kubernetes/pkg/kubelet/util/queue"
	"k8s.io/kubernetes/pkg/kubelet/util/sliceutils"
	"k8s.io/kubernetes/pkg/kubelet/volumemanager"
	"k8s.io/kubernetes/pkg/kubelet/watchdog"
	httpprobe "k8s.io/kubernetes/pkg/probe/http"
	"k8s.io/kubernetes/pkg/security/apparmor"
	"k8s.io/kubernetes/pkg/util/oom"
	"k8s.io/kubernetes/pkg/volume"
	"k8s.io/kubernetes/pkg/volume/csi"
	"k8s.io/kubernetes/pkg/volume/util/hostutil"
	"k8s.io/kubernetes/pkg/volume/util/subpath"
	"k8s.io/kubernetes/pkg/volume/util/volumepathhandler"
	"k8s.io/utils/clock"
)

const (
	// Max amount of time to wait for the container runtime to come up.
	maxWaitForContainerRuntime = 30 * time.Second

	// nodeStatusUpdateRetry specifies how many times kubelet retries when posting node status failed.
	nodeStatusUpdateRetry = 5

	// nodeReadyGracePeriod is the period to allow for before fast status update is
	// terminated and container runtime not being ready is logged without verbosity guard.
	nodeReadyGracePeriod = 120 * time.Second

	// DefaultContainerLogsDir is the location of container logs.
	DefaultContainerLogsDir = "/var/log/containers"

	// MaxCrashLoopBackOff is the max backoff period for container restarts, exported for the e2e test
	MaxCrashLoopBackOff = v1beta1.MaxContainerBackOff

	// reducedMaxCrashLoopBackOff is the default max backoff period for container restarts when the alpha feature
	// gate ReduceDefaultCrashLoopBackOffDecay is enabled
	reducedMaxCrashLoopBackOff = 60 * time.Second

	// Initial period for the exponential backoff for container restarts.
	initialCrashLoopBackOff = time.Second * 10

	// reducedInitialCrashLoopBackOff is the default initial backoff period for container restarts when the alpha feature
	// gate ReduceDefaultCrashLoopBackOffDecay is enabled
	reducedInitialCrashLoopBackOff = 1 * time.Second

	// MaxImageBackOff is the max backoff period for image pulls, exported for the e2e test
	MaxImageBackOff = 300 * time.Second

	// Period for performing global cleanup tasks.
	housekeepingPeriod = time.Second * 2

	// Duration at which housekeeping failed to satisfy the invariant that
	// housekeeping should be fast to avoid blocking pod config (while
	// housekeeping is running no new pods are started or deleted).
	housekeepingWarningDuration = time.Second * 1

	// Period after which the runtime cache expires - set to slightly longer than
	// the expected length between housekeeping periods, which explicitly refreshes
	// the cache.
	runtimeCacheRefreshPeriod = housekeepingPeriod + housekeepingWarningDuration

	// Period for performing eviction monitoring.
	// ensure this is kept in sync with internal cadvisor housekeeping.
	evictionMonitoringPeriod = time.Second * 10

	// The path in containers' filesystems where the hosts file is mounted.
	linuxEtcHostsPath   = "/etc/hosts"
	windowsEtcHostsPath = "C:\\Windows\\System32\\drivers\\etc\\hosts"

	// Capacity of the channel for receiving pod lifecycle events. This number
	// is a bit arbitrary and may be adjusted in the future.
	plegChannelCapacity = 1000

	// Generic PLEG relies on relisting for discovering container events.
	// A longer period means that kubelet will take longer to detect container
	// changes and to update pod status. On the other hand, a shorter period
	// will cause more frequent relisting (e.g., container runtime operations),
	// leading to higher cpu usage.
	// Note that even though we set the period to 1s, the relisting itself can
	// take more than 1s to finish if the container runtime responds slowly
	// and/or when there are many container changes in one cycle.
	genericPlegRelistPeriod    = time.Second * 1
	genericPlegRelistThreshold = time.Minute * 3

	// Generic PLEG relist period and threshold when used with Evented PLEG.
	eventedPlegRelistPeriod     = time.Second * 300
	eventedPlegRelistThreshold  = time.Minute * 10
	eventedPlegMaxStreamRetries = 5

	// backOffPeriod is the period to back off when pod syncing results in an
	// error.
	backOffPeriod = time.Second * 10

	// Initial period for the exponential backoff for image pulls.
	imageBackOffPeriod = time.Second * 10

	// ContainerGCPeriod is the period for performing container garbage collection.
	ContainerGCPeriod = time.Minute
	// ImageGCPeriod is the period for performing image garbage collection.
	ImageGCPeriod = 5 * time.Minute

	// Minimum number of dead containers to keep in a pod
	minDeadContainerInPod = 1

	// nodeLeaseRenewIntervalFraction is the fraction of lease duration to renew the lease
	nodeLeaseRenewIntervalFraction = 0.25

	// instrumentationScope is the name of OpenTelemetry instrumentation scope
	instrumentationScope = "k8s.io/kubernetes/pkg/kubelet"
)

var (
	// ContainerLogsDir can be overwritten for testing usage
	ContainerLogsDir = DefaultContainerLogsDir
	etcHostsPath     = getContainerEtcHostsPath()

	admissionRejectionReasons = sets.New[string](
		lifecycle.AppArmorNotAdmittedReason,
		lifecycle.PodOSSelectorNodeLabelDoesNotMatch,
		lifecycle.PodOSNotSupported,
		lifecycle.InvalidNodeInfo,
		lifecycle.InitContainerRestartPolicyForbidden,
		lifecycle.SupplementalGroupsPolicyNotSupported,
		lifecycle.UnexpectedAdmissionError,
		lifecycle.UnknownReason,
		lifecycle.UnexpectedPredicateFailureType,
		lifecycle.OutOfCPU,
		lifecycle.OutOfMemory,
		lifecycle.OutOfEphemeralStorage,
		lifecycle.OutOfPods,
		lifecycle.PodLevelResourcesNotAdmittedReason,
		lifecycle.PodFeatureUnsupported,
		tainttoleration.ErrReasonNotMatch,
		eviction.Reason,
		sysctl.ForbiddenReason,
		topologymanager.ErrorTopologyAffinity,
		nodeshutdown.NodeShutdownNotAdmittedReason,
		volumemanager.VolumeAttachmentLimitExceededReason,
	)

	// This is exposed for unit tests.
	goos = sysruntime.GOOS
)

func getContainerEtcHostsPath() string {
	if goos == "windows" {
		return windowsEtcHostsPath
	}
	return linuxEtcHostsPath
}

// SyncHandler is an interface implemented by Kubelet, for testability
type SyncHandler interface {
	HandlePodAdditions(ctx context.Context, pods []*v1.Pod)
	HandlePodUpdates(ctx context.Context, pods []*v1.Pod)
	HandlePodRemoves(ctx context.Context, pods []*v1.Pod)
	HandlePodReconcile(ctx context.Context, pods []*v1.Pod)
	HandlePodSyncs(ctx context.Context, pods []*v1.Pod)
	HandlePodCleanups(ctx context.Context) error
}

// Option is a functional option type for Kubelet
type Option func(*Kubelet)

// Bootstrap is a bootstrapping interface for kubelet, targets the initialization protocol
type Bootstrap interface {
	GetConfiguration() kubeletconfiginternal.KubeletConfiguration
	BirthCry()
	StartGarbageCollection(ctx context.Context)
	ListenAndServe(ctx context.Context, kubeCfg *kubeletconfiginternal.KubeletConfiguration, tlsConfig *tls.Config, auth server.AuthInterface, tp trace.TracerProvider)
	ListenAndServeReadOnly(ctx context.Context, address net.IP, port uint, tp trace.TracerProvider)
	ListenAndServePodResources(ctx context.Context)
	ListenAndServePods(ctx context.Context)
	Run(ctx context.Context, updates <-chan kubetypes.PodUpdate)
}

// Dependencies is a bin for things we might consider "injected dependencies" -- objects constructed
// at runtime that are necessary for running the Kubelet. This is a temporary solution for grouping
// these objects while we figure out a more comprehensive dependency injection story for the Kubelet.
type Dependencies struct {
	Options []Option

	// Injected Dependencies
	Flagz                     flagz.Reader
	Auth                      server.AuthInterface
	CAdvisorInterface         cadvisor.Interface
	ContainerManager          cm.ContainerManager
	EventClient               v1core.EventsGetter
	HeartbeatClient           clientset.Interface
	OnHeartbeatFailure        func()
	KubeClient                clientset.Interface
	Mounter                   mount.Interface
	HostUtil                  hostutil.HostUtils
	OOMAdjuster               *oom.OOMAdjuster
	OSInterface               kubecontainer.OSInterface
	PodConfig                 *config.PodConfig
	ProbeManager              prober.Manager
	Recorder                  record.EventRecorderLogger
	Subpather                 subpath.Interface
	TracerProvider            trace.TracerProvider
	VolumePlugins             []volume.VolumePlugin
	DynamicPluginProber       volume.DynamicPluginProber
	TLSOptions                *server.TLSOptions
	TLSConfig                 *tls.Config
	RemoteRuntimeService      internalapi.RuntimeService
	RemoteImageService        internalapi.ImageManagerService
	PodStartupLatencyTracker  util.PodStartupLatencyTracker
	NodeStartupLatencyTracker util.NodeStartupLatencyTracker
	HealthChecker             watchdog.HealthChecker
	// remove it after cadvisor.UsingLegacyCadvisorStats dropped.
	useLegacyCadvisorStats bool
}

// newCrashLoopBackOff configures the backoff maximum to be used
// by kubelet for container restarts depending on the alpha gates
// and kubelet configuration set
func newCrashLoopBackOff(kubeCfg *kubeletconfiginternal.KubeletConfiguration) (time.Duration, time.Duration) {
	boMax := MaxCrashLoopBackOff
	boInitial := initialCrashLoopBackOff
	if utilfeature.DefaultFeatureGate.Enabled(features.ReduceDefaultCrashLoopBackOffDecay) {
		boMax = reducedMaxCrashLoopBackOff
		boInitial = reducedInitialCrashLoopBackOff
	}

	if utilfeature.DefaultFeatureGate.Enabled(features.KubeletCrashLoopBackOffMax) {
		// operator-invoked configuration always has precedence if valid
		boMax = kubeCfg.CrashLoopBackOff.MaxContainerRestartPeriod.Duration
		if boMax < boInitial {
			boInitial = boMax
		}
	}
	return boMax, boInitial
}

// makePodSourceConfig creates a config.PodConfig from the given
// KubeletConfiguration or returns an error.
func makePodSourceConfig(ctx context.Context, kubeCfg *kubeletconfiginternal.KubeletConfiguration, kubeDeps *Dependencies, nodeName types.NodeName, nodeHasSynced func() bool) (*config.PodConfig, error) {
	logger := klog.FromContext(ctx)
	manifestURLHeader := make(http.Header)
	if len(kubeCfg.StaticPodURLHeader) > 0 {
		for k, v := range kubeCfg.StaticPodURLHeader {
			for i := range v {
				manifestURLHeader.Add(k, v[i])
			}
		}
	}

	// source of all configuration
	cfg := config.NewPodConfig(kubeDeps.Recorder, kubeDeps.PodStartupLatencyTracker)

	// define file config source
	if kubeCfg.StaticPodPath != "" {
		logger.Info("Adding static pod path", "path", kubeCfg.StaticPodPath)
		config.NewSourceFile(logger, kubeCfg.StaticPodPath, nodeName, kubeCfg.FileCheckFrequency.Duration, cfg.Channel(ctx, kubetypes.FileSource))
	}

	// define url config source
	if kubeCfg.StaticPodURL != "" {
		logger.Info("Adding pod URL with HTTP header", "URL", kubeCfg.StaticPodURL, "header", manifestURLHeader)
		config.NewSourceURL(logger, kubeCfg.StaticPodURL, manifestURLHeader, nodeName, kubeCfg.HTTPCheckFrequency.Duration, cfg.Channel(ctx, kubetypes.HTTPSource))
	}

	if kubeDeps.KubeClient != nil {
		logger.Info("Adding apiserver pod source")
		config.NewSourceApiserver(logger, kubeDeps.KubeClient, nodeName, nodeHasSynced, cfg.Channel(ctx, kubetypes.ApiserverSource))
	}
	return cfg, nil
}

// PreInitRuntimeService will init runtime service before RunKubelet.
func PreInitRuntimeService(ctx context.Context, kubeCfg *kubeletconfiginternal.KubeletConfiguration, kubeDeps *Dependencies) error {
	remoteImageEndpoint := kubeCfg.ImageServiceEndpoint
	if remoteImageEndpoint == "" && kubeCfg.ContainerRuntimeEndpoint != "" {
		remoteImageEndpoint = kubeCfg.ContainerRuntimeEndpoint
	}
	var err error
	useStreaming := utilfeature.DefaultFeatureGate.Enabled(features.CRIListStreaming)
	if kubeDeps.RemoteRuntimeService, err = remote.NewRemoteRuntimeService(ctx, kubeCfg.ContainerRuntimeEndpoint, kubeCfg.RuntimeRequestTimeout.Duration, kubeDeps.TracerProvider, useStreaming); err != nil {
		return err
	}
	if kubeDeps.RemoteImageService, err = remote.NewRemoteImageService(ctx, remoteImageEndpoint, kubeCfg.RuntimeRequestTimeout.Duration, kubeDeps.TracerProvider, useStreaming); err != nil {
		return err
	}

	kubeDeps.useLegacyCadvisorStats = cadvisor.UsingLegacyCadvisorStats(kubeCfg.ContainerRuntimeEndpoint)

	return nil
}

// NewMainKubelet instantiates a new Kubelet object along with all the required internal modules.
// No initialization of Kubelet and its modules should happen here.
func NewMainKubelet(ctx context.Context,
	kubeCfg *kubeletconfiginternal.KubeletConfiguration,
	kubeDeps *Dependencies,
	crOptions *kubeletconfig.ContainerRuntimeOptions,
	hostname string,
	nodeName types.NodeName,
	nodeIPs []net.IP,
	providerID string,
	cloudProvider string,
	certDirectory string,
	rootDirectory string,
	podLogsDirectory string,
	imageCredentialProviderConfigPath string,
	imageCredentialProviderBinDir string,
	registerNode bool,
	registerWithTaints []v1.Taint,
	allowedUnsafeSysctls []string,
	experimentalMounterPath string,
	kernelMemcgNotification bool,
	experimentalNodeAllocatableIgnoreEvictionThreshold bool,
	minimumGCAge metav1.Duration,
	maxPerPodContainerCount int32,
	maxContainerCount int32,
	nodeLabels map[string]string,
	nodeStatusMaxImages int32,
	seccompDefault bool,
) (*Kubelet, error) {
	logger := klog.FromContext(ctx)

	if rootDirectory == "" {
		return nil, fmt.Errorf("invalid root directory %q", rootDirectory)
	}
	if podLogsDirectory == "" {
		return nil, errors.New("pod logs root directory is empty")
	}
	if kubeCfg.SyncFrequency.Duration <= 0 {
		return nil, fmt.Errorf("invalid sync frequency %d", kubeCfg.SyncFrequency.Duration)
	}

	if !cloudprovider.IsExternal(cloudProvider) && len(cloudProvider) != 0 {
		cloudprovider.DisableWarningForProvider(cloudProvider)
		return nil, cloudprovider.ErrorForDisabledProvider(cloudProvider)
	}

	var nodeHasSynced cache.InformerSynced
	var nodeInformer coreinformersv1.NodeInformer
	var nodeLister corelisters.NodeLister

	// If kubeClient == nil, we are running in standalone mode (i.e. no API servers)
	// If not nil, we are running as part of a cluster and should sync w/API
	if kubeDeps.KubeClient != nil {
		kubeInformers := informers.NewSharedInformerFactoryWithOptions(kubeDeps.KubeClient, 0, informers.WithTweakListOptions(func(options *metav1.ListOptions) {
			options.FieldSelector = fields.Set{metav1.ObjectNameField: string(nodeName)}.String()
		}))
		nodeInformer = kubeInformers.Core().V1().Nodes()
		nodeLister = nodeInformer.Lister()
		nodeHasSynced = func() bool {
			return kubeInformers.Core().V1().Nodes().Informer().HasSynced()
		}
		kubeInformers.Start(wait.NeverStop)
		logger.Info("Attempting to sync node with API server")
	} else {
		// we don't have a client to sync!
		nodeIndexer := cache.NewIndexer(cache.MetaNamespaceKeyFunc, cache.Indexers{})
		nodeLister = corelisters.NewNodeLister(nodeIndexer)
		nodeHasSynced = func() bool { return true }
		logger.Info("Kubelet is running in standalone mode, will skip API server sync")
	}

	if kubeDeps.PodConfig == nil {
		var err error
		kubeDeps.PodConfig, err = makePodSourceConfig(ctx, kubeCfg, kubeDeps, nodeName, nodeHasSynced)
		if err != nil {
			return nil, err
		}
	}

	containerGCPolicy := kubecontainer.GCPolicy{
		MinAge:             minimumGCAge.Duration,
		MaxPerPodContainer: int(maxPerPodContainerCount),
		MaxContainers:      int(maxContainerCount),
	}

	daemonEndpoints := &v1.NodeDaemonEndpoints{
		KubeletEndpoint: v1.DaemonEndpoint{Port: kubeCfg.Port},
	}

	imageGCPolicy := images.ImageGCPolicy{
		MinAge:               kubeCfg.ImageMinimumGCAge.Duration,
		HighThresholdPercent: int(kubeCfg.ImageGCHighThresholdPercent),
		LowThresholdPercent:  int(kubeCfg.ImageGCLowThresholdPercent),
	}

	imageGCPolicy.MaxAge = kubeCfg.ImageMaximumGCAge.Duration

	enforceNodeAllocatable := kubeCfg.EnforceNodeAllocatable
	if experimentalNodeAllocatableIgnoreEvictionThreshold {
		// Do not provide kubeCfg.EnforceNodeAllocatable to eviction threshold parsing if we are not enforcing Evictions
		enforceNodeAllocatable = []string{}
	}
	thresholds, err := eviction.ParseThresholdConfig(enforceNodeAllocatable, kubeCfg.EvictionHard, kubeCfg.EvictionSoft, kubeCfg.EvictionSoftGracePeriod, kubeCfg.EvictionMinimumReclaim)
	if err != nil {
		return nil, err
	}
	evictionConfig := eviction.Config{
		PressureTransitionPeriod: kubeCfg.EvictionPressureTransitionPeriod.Duration,
		MaxPodGracePeriodSeconds: int64(kubeCfg.EvictionMaxPodGracePeriod),
		Thresholds:               thresholds,
		KernelMemcgNotification:  kernelMemcgNotification,
		PodCgroupRoot:            kubeDeps.ContainerManager.GetPodCgroupRoot(),
	}

	var serviceLister corelisters.ServiceLister
	var serviceHasSynced cache.InformerSynced
	if kubeDeps.KubeClient != nil {
		// don't watch headless services, they are not needed since this informer is only used to create the environment variables for pods.
		// See https://issues.k8s.io/122394
		kubeInformers := informers.NewSharedInformerFactoryWithOptions(kubeDeps.KubeClient, 0, informers.WithTweakListOptions(func(options *metav1.ListOptions) {
			options.FieldSelector = fields.OneTermNotEqualSelector("spec.clusterIP", v1.ClusterIPNone).String()
		}))
		serviceLister = kubeInformers.Core().V1().Services().Lister()
		serviceHasSynced = kubeInformers.Core().V1().Services().Informer().HasSynced
		kubeInformers.Start(wait.NeverStop)
	} else {
		serviceIndexer := cache.NewIndexer(cache.MetaNamespaceKeyFunc, cache.Indexers{cache.NamespaceIndex: cache.MetaNamespaceIndexFunc})
		serviceLister = corelisters.NewServiceLister(serviceIndexer)
		serviceHasSynced = func() bool { return true }
	}

	// construct a node reference used for events
	nodeRef := &v1.ObjectReference{
		APIVersion: "v1",
		Kind:       "Node",
		Name:       string(nodeName),
		Namespace:  "",
	}

	oomWatcher, err := oomwatcher.NewWatcher(kubeDeps.Recorder)
	if err != nil {
		if inuserns.RunningInUserNS() {
			if utilfeature.DefaultFeatureGate.Enabled(features.KubeletInUserNamespace) {
				// oomwatcher.NewWatcher returns "open /dev/kmsg: operation not permitted" error,
				// when running in a user namespace with sysctl value `kernel.dmesg_restrict=1`.
				logger.V(2).Info("Failed to create an oomWatcher (running in UserNS, ignoring)", "err", err)
				oomWatcher = nil
			} else {
				logger.Error(err, "Failed to create an oomWatcher (running in UserNS, Hint: enable KubeletInUserNamespace feature flag to ignore the error)")
				return nil, err
			}
		} else {
			return nil, err
		}
	}

	clusterDNS := make([]net.IP, 0, len(kubeCfg.ClusterDNS))
	for _, ipEntry := range kubeCfg.ClusterDNS {
		ip := netutils.ParseIPSloppy(ipEntry)
		if ip == nil {
			logger.Info("Invalid clusterDNS IP", "IP", ipEntry)
		} else {
			clusterDNS = append(clusterDNS, ip)
		}
	}

	// A TLS transport is needed to make HTTPS-based container lifecycle requests,
	// but we do not have the information necessary to do TLS verification.
	//
	// This client must not be modified to include credentials, because it is
	// critical that credentials not leak from the client to arbitrary hosts.
	insecureContainerLifecycleHTTPClient := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
		CheckRedirect: httpprobe.RedirectChecker(false),
	}

	tracer := kubeDeps.TracerProvider.Tracer(instrumentationScope)

	klet := &Kubelet{
		hostname:                     hostname,
		nodeName:                     nodeName,
		kubeClient:                   kubeDeps.KubeClient,
		heartbeatClient:              kubeDeps.HeartbeatClient,
		onRepeatedHeartbeatFailure:   kubeDeps.OnHeartbeatFailure,
		rootDirectory:                filepath.Clean(rootDirectory),
		podLogsDirectory:             podLogsDirectory,
		resyncInterval:               kubeCfg.SyncFrequency.Duration,
		sourcesReady:                 config.NewSourcesReady(kubeDeps.PodConfig.SeenAllSources),
		registerNode:                 registerNode,
		registerWithTaints:           registerWithTaints,
		dnsConfigurer:                dns.NewConfigurer(kubeDeps.Recorder, nodeRef, nodeIPs, clusterDNS, kubeCfg.ClusterDomain, kubeCfg.ResolverConfig),
		serviceLister:                serviceLister,
		serviceHasSynced:             serviceHasSynced,
		nodeLister:                   nodeLister,
		nodeHasSynced:                nodeHasSynced,
		recorder:                     kubeDeps.Recorder,
		cadvisor:                     kubeDeps.CAdvisorInterface,
		externalCloudProvider:        cloudprovider.IsExternal(cloudProvider),
		providerID:                   providerID,
		nodeRef:                      nodeRef,
		nodeLabels:                   nodeLabels,
		nodeStatusUpdateFrequency:    kubeCfg.NodeStatusUpdateFrequency.Duration,
		nodeStatusReportFrequency:    kubeCfg.NodeStatusReportFrequency.Duration,
		os:                           kubeDeps.OSInterface,
		oomWatcher:                   oomWatcher,
		cgroupsPerQOS:                kubeCfg.CgroupsPerQOS,
		cgroupRoot:                   kubeCfg.CgroupRoot,
		mounter:                      kubeDeps.Mounter,
		hostutil:                     kubeDeps.HostUtil,
		subpather:                    kubeDeps.Subpather,
		maxPods:                      int(kubeCfg.MaxPods),
		podsPerCore:                  int(kubeCfg.PodsPerCore),
		syncLoopMonitor:              atomic.Value{},
		daemonEndpoints:              daemonEndpoints,
		containerManager:             kubeDeps.ContainerManager,
		nodeIPs:                      nodeIPs,
		nodeIPValidator:              validateNodeIP,
		clock:                        clock.RealClock{},
		enableControllerAttachDetach: kubeCfg.EnableControllerAttachDetach,
		makeIPTablesUtilChains:       kubeCfg.MakeIPTablesUtilChains,
		nodeStatusMaxImages:          nodeStatusMaxImages,
		tracer:                       tracer,
		nodeStartupLatencyTracker:    kubeDeps.NodeStartupLatencyTracker,
		podStartupLatencyTracker:     kubeDeps.PodStartupLatencyTracker,
		healthChecker:                kubeDeps.HealthChecker,
		flagz:                        kubeDeps.Flagz,
	}

	var secretManager secret.Manager
	var configMapManager configmap.Manager
	if klet.kubeClient != nil {
		switch kubeCfg.ConfigMapAndSecretChangeDetectionStrategy {
		case kubeletconfiginternal.WatchChangeDetectionStrategy:
			secretManager = secret.NewWatchingSecretManager(klet.kubeClient, klet.resyncInterval)
			configMapManager = configmap.NewWatchingConfigMapManager(klet.kubeClient, klet.resyncInterval)
		case kubeletconfiginternal.TTLCacheChangeDetectionStrategy:
			secretManager = secret.NewCachingSecretManager(
				klet.kubeClient, manager.GetObjectTTLFromNodeFunc(klet.GetNode))
			configMapManager = configmap.NewCachingConfigMapManager(
				klet.kubeClient, manager.GetObjectTTLFromNodeFunc(klet.GetNode))
		case kubeletconfiginternal.GetChangeDetectionStrategy:
			secretManager = secret.NewSimpleSecretManager(klet.kubeClient)
			configMapManager = configmap.NewSimpleConfigMapManager(klet.kubeClient)
		default:
			return nil, fmt.Errorf("unknown configmap and secret manager mode: %v", kubeCfg.ConfigMapAndSecretChangeDetectionStrategy)
		}

		klet.secretManager = secretManager
		klet.configMapManager = configMapManager
	}

	machineInfo, err := klet.cadvisor.MachineInfo()
	if err != nil {
		return nil, err
	}
	// Avoid collector collects it as a timestamped metric
	// See PR #95210 and #97006 for more details.
	machineInfo.Timestamp = time.Time{}
	klet.setCachedMachineInfo(machineInfo)

	imageBackOff := flowcontrol.NewBackOff(imageBackOffPeriod, MaxImageBackOff)

	klet.livenessManager = proberesults.NewManager()
	klet.readinessManager = proberesults.NewManager()
	klet.startupManager = proberesults.NewManager()
	podCache := kubecontainer.NewCache()
	klet.podCache = podCache

	klet.mirrorPodClient = kubepod.NewBasicMirrorClient(klet.kubeClient, string(nodeName), nodeLister)
	klet.podManager = kubepod.NewBasicPodManager()

	klet.statusManager = status.NewManager(klet.kubeClient, klet.podManager, klet, kubeDeps.PodStartupLatencyTracker)

	if utilfeature.DefaultFeatureGate.Enabled(features.PodsAPI) {
		broadcaster := pods.NewBroadcaster()
		klet.podsServer = pods.NewPodsServer(broadcaster, klet.podManager, klet.statusManager)
		klet.statusManager.AddPodUpdateNotifier(klet.podsServer)
	}
	klet.allocationManager = allocation.NewManager(
		klet.getRootDir(),
		klet.statusManager,
		klet.syncPodNow,
		klet.GetActivePods,
		klet.podManager.GetPodByUID,
		klet.sourcesReady,
		kubeDeps.Recorder,
	)

	klet.resourceAnalyzer = serverstats.NewResourceAnalyzer(ctx, klet, kubeCfg.VolumeStatsAggPeriod.Duration, kubeDeps.Recorder)
	klet.runtimeService = kubeDeps.RemoteRuntimeService

	if kubeDeps.KubeClient != nil {
		klet.runtimeClassManager = runtimeclass.NewManager(kubeDeps.KubeClient)
	}

	// setup containerLogManager for CRI container runtime
	containerLogManager, err := logs.NewContainerLogManager(
		klet.runtimeService,
		kubeDeps.OSInterface,
		kubeCfg.ContainerLogMaxSize,
		int(kubeCfg.ContainerLogMaxFiles),
		int(kubeCfg.ContainerLogMaxWorkers),
		kubeCfg.ContainerLogMonitorInterval,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize container log manager: %v", err)
	}
	klet.containerLogManager = containerLogManager

	klet.reasonCache = NewReasonCache()
	klet.workQueue = queue.NewBasicWorkQueue(klet.clock)
	klet.podWorkers = newPodWorkers(
		klet,
		kubeDeps.Recorder,
		klet.workQueue,
		klet.resyncInterval,
		backOffPeriod,
		klet.podCache,
		klet.allocationManager,
	)

	var singleProcessOOMKill *bool
	if sysruntime.GOOS == "linux" {
		if !util.IsCgroup2UnifiedMode() {
			// This is a default behavior for cgroups v1.
			singleProcessOOMKill = ptr.To(true)
		} else {
			if kubeCfg.SingleProcessOOMKill == nil {
				singleProcessOOMKill = ptr.To(false)
			} else {
				singleProcessOOMKill = kubeCfg.SingleProcessOOMKill
			}
		}
	}

	tokenManager := token.NewManager(kubeDeps.KubeClient)
	getServiceAccount := func(namespace, name string) (*v1.ServiceAccount, error) {
		return nil, fmt.Errorf("get service account is not implemented")
	}
	if utilfeature.DefaultFeatureGate.Enabled(features.KubeletServiceAccountTokenForCredentialProviders) {
		getServiceAccount = func(namespace, name string) (*v1.ServiceAccount, error) {
			if klet.kubeClient == nil {
				return nil, errors.New("cannot get ServiceAccounts when kubelet is in standalone mode")
			}
			return klet.kubeClient.CoreV1().ServiceAccounts(namespace).Get(ctx, name, metav1.GetOptions{})
		}
	}

	runtime, postImageGCHooks, err := kuberuntime.NewKubeGenericRuntimeManager(
		ctx,
		kubecontainer.FilterEventRecorder(kubeDeps.Recorder),
		klet.livenessManager,
		klet.readinessManager,
		klet.startupManager,
		rootDirectory,
		podLogsDirectory,
		machineInfo,
		klet.podWorkers,
		kubeCfg.MaxPods,
		kubeDeps.OSInterface,
		klet,
		insecureContainerLifecycleHTTPClient,
		imageBackOff,
		kubeCfg.SerializeImagePulls,
		kubeCfg.MaxParallelImagePulls,
		float32(kubeCfg.RegistryPullQPS),
		int(kubeCfg.RegistryBurst),
		kubeCfg.ImagePullCredentialsVerificationPolicy,
		kubeCfg.PreloadedImagesVerificationAllowlist,
		imageCredentialProviderConfigPath,
		imageCredentialProviderBinDir,
		singleProcessOOMKill,
		kubeCfg.CPUCFSQuota,
		kubeCfg.CPUCFSQuotaPeriod,
		kubeDeps.RemoteRuntimeService,
		kubeDeps.RemoteImageService,
		kubeDeps.ContainerManager,
		klet.containerLogManager,
		klet.runtimeClassManager,
		seccompDefault,
		kubeCfg.MemorySwap.SwapBehavior,
		kubeDeps.ContainerManager.GetNodeAllocatableAbsolute,
		*kubeCfg.MemoryThrottlingFactor,
		kubeCfg.MemoryReservationPolicy,
		klet.podStartupLatencyTracker,
		kubeDeps.TracerProvider,
		tokenManager,
		getServiceAccount,
		klet.podStartupLatencyTracker,
	)
	if err != nil {
		return nil, err
	}
	klet.containerRuntime = runtime
	klet.streamingRuntime = runtime
	klet.runner = runtime
	klet.allocationManager.SetContainerRuntime(runtime)
	resizeAdmitHandler := allocation.NewPodResizesAdmitHandler(klet.containerManager, runtime, klet.allocationManager, logger)

	runtimeCache, err := kubecontainer.NewRuntimeCache(klet.containerRuntime, runtimeCacheRefreshPeriod)
	if err != nil {
		return nil, err
	}
	klet.runtimeCache = runtimeCache

	// common provider to get host file system usage associated with a pod managed by kubelet
	hostStatsProvider := stats.NewHostStatsProvider(kubecontainer.RealOS{}, func(podUID types.UID) string {
		return getEtcHostsPath(klet.getPodDir(podUID))
	}, podLogsDirectory)

	cadvisorStatsProvider := stats.NewCadvisorStatsProvider(
		klet.cadvisor,
		klet.resourceAnalyzer,
		klet.podManager,
		klet.containerRuntime,
		klet.statusManager,
		hostStatsProvider,
		kubeDeps.ContainerManager,
	)
	if kubeDeps.useLegacyCadvisorStats {
		klet.StatsProvider = cadvisorStatsProvider
	} else {
		klet.StatsProvider = stats.NewCRIStatsProvider(
			klet.cadvisor,
			klet.resourceAnalyzer,
			klet.podManager,
			kubeDeps.RemoteRuntimeService,
			kubeDeps.RemoteImageService,
			hostStatsProvider,
			utilfeature.DefaultFeatureGate.Enabled(features.PodAndContainerStatsFromCRI),
			cadvisorStatsProvider,
		)
	}

	eventChannel := make(chan *pleg.PodLifecycleEvent, plegChannelCapacity)

	if utilfeature.DefaultFeatureGate.Enabled(features.EventedPLEG) {
		// adjust Generic PLEG relisting period and threshold to higher value when Evented PLEG is turned on
		genericRelistDuration := &pleg.RelistDuration{
			RelistPeriod:    eventedPlegRelistPeriod,
			RelistThreshold: eventedPlegRelistThreshold,
		}
		klet.pleg = pleg.NewGenericPLEG(logger, klet.containerRuntime, eventChannel, genericRelistDuration, podCache, clock.RealClock{})
		// In case Evented PLEG has to fall back on Generic PLEG due to an error,
		// Evented PLEG should be able to reset the Generic PLEG relisting duration
		// to the default value.
		eventedRelistDuration := &pleg.RelistDuration{
			RelistPeriod:    genericPlegRelistPeriod,
			RelistThreshold: genericPlegRelistThreshold,
		}
		klet.eventedPleg, err = pleg.NewEventedPLEG(logger, klet.containerRuntime, klet.runtimeService, eventChannel,
			podCache, klet.pleg, eventedPlegMaxStreamRetries, eventedRelistDuration, clock.RealClock{})
		if err != nil {
			return nil, err
		}
	} else {
		genericRelistDuration := &pleg.RelistDuration{
			RelistPeriod:    genericPlegRelistPeriod,
			RelistThreshold: genericPlegRelistThreshold,
		}
		klet.pleg = pleg.NewGenericPLEG(logger, klet.containerRuntime, eventChannel, genericRelistDuration, podCache, clock.RealClock{})
	}

	klet.runtimeState = newRuntimeState(maxWaitForContainerRuntime)
	klet.runtimeState.addHealthCheck("PLEG", klet.pleg.Healthy)
	if utilfeature.DefaultFeatureGate.Enabled(features.EventedPLEG) {
		klet.runtimeState.addHealthCheck("EventedPLEG", klet.eventedPleg.Healthy)
	}
	if _, err := klet.updatePodCIDR(ctx, kubeCfg.PodCIDR); err != nil {
		logger.Error(err, "Pod CIDR update failed")
	}

	// setup containerGC
	containerGC, err := kubecontainer.NewContainerGC(klet.containerRuntime, containerGCPolicy, klet.sourcesReady)
	if err != nil {
		return nil, err
	}
	klet.containerGC = containerGC
	klet.containerDeletor = newPodContainerDeletor(klet.containerRuntime, max(containerGCPolicy.MaxPerPodContainer, minDeadContainerInPod))

	// setup imageManager
	imageManager, err := images.NewImageGCManager(klet.containerRuntime, klet.StatsProvider, postImageGCHooks, kubeDeps.Recorder, nodeRef, imageGCPolicy, kubeDeps.TracerProvider)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize image manager: %v", err)
	}
	klet.imageManager = imageManager

	if kubeDeps.TLSOptions != nil {
		kubeDeps.TLSConfig = &tls.Config{}

		kubeDeps.TLSConfig.MinVersion = kubeDeps.TLSOptions.MinVersion
		kubeDeps.TLSConfig.CipherSuites = kubeDeps.TLSOptions.CipherSuites
		kubeDeps.TLSConfig.CurvePreferences = kubeDeps.TLSOptions.CurvePreferences

		getServingCertificate := func() *tls.Certificate { return nil }

		// kubelet configuration that automatically rotates serving certs
		if kubeCfg.ServerTLSBootstrap && utilfeature.DefaultFeatureGate.Enabled(features.RotateKubeletServerCertificate) {
			klet.serverCertificateManager, err = kubeletcertificate.NewKubeletServerCertificateManager(klet.kubeClient, kubeCfg, klet.nodeName, func() []v1.NodeAddress {
				return klet.getLastObservedNodeAddresses(ctx)
			}, certDirectory)
			if err != nil {
				return nil, fmt.Errorf("failed to initialize certificate manager: %w", err)
			}
			getServingCertificate = klet.serverCertificateManager.Current

		} else if kubeDeps.TLSOptions.CertFile != "" && kubeDeps.TLSOptions.KeyFile != "" {

			if utilfeature.DefaultFeatureGate.Enabled(features.ReloadKubeletServerCertificateFile) {
				// kubelet configuration that reloads serving certs from the disk when updated
				klet.serverCertificateManager, err = kubeletcertificate.NewKubeletServerCertificateDynamicFileManager(kubeDeps.TLSOptions.CertFile, kubeDeps.TLSOptions.KeyFile)
				if err != nil {
					return nil, fmt.Errorf("failed to initialize file based certificate manager: %w", err)
				}
				getServingCertificate = klet.serverCertificateManager.Current

			} else {
				// kubelet configuration that sets static serving certs
				servingCert, err := tls.LoadX509KeyPair(kubeDeps.TLSOptions.CertFile, kubeDeps.TLSOptions.KeyFile)
				if err != nil {
					return nil, fmt.Errorf("failed to load certificate: %w", err)
				}
				getServingCertificate = func() *tls.Certificate { return &servingCert }
			}
		}

		kubeDeps.TLSConfig.GetCertificate = func(*tls.ClientHelloInfo) (*tls.Certificate, error) {
			cert := getServingCertificate()
			if cert == nil {
				return nil, fmt.Errorf("no serving certificate available for the kubelet")
			}
			return cert, nil
		}

		if kubeDeps.TLSOptions.ClientCAFile != "" {
			// Populate PeerCertificates in requests, but don't reject connections without verified certificates
			kubeDeps.TLSConfig.ClientAuth = tls.RequestClientCert

			if utilfeature.DefaultFeatureGate.Enabled(features.ReloadKubeletClientCAFile) {
				// kubelet configuration that reloads Client CA Bundle from the disk when updated
				klet.clientCAManager = dynamiccertificates.NewDynamicServingCertificateController(kubeDeps.TLSConfig.Clone(), kubeDeps.Auth, nil, nil, nil)

				err := klet.clientCAManager.RunOnce()
				if err != nil {
					return nil, fmt.Errorf("unable to load client CA file %s: %w", kubeDeps.TLSOptions.ClientCAFile, err)
				}

				kubeDeps.TLSConfig.GetConfigForClient = klet.clientCAManager.GetConfigForClient

			} else {
				// kubelet configuration that sets static Client CA Bundle
				clientCAs, err := certutil.NewPool(kubeDeps.TLSOptions.ClientCAFile)
				if err != nil {
					return nil, fmt.Errorf("unable to load client CA file %s: %w", kubeDeps.TLSOptions.ClientCAFile, err)
				}
				kubeDeps.TLSConfig.ClientCAs = clientCAs
			}
		}
	}

	if kubeDeps.ProbeManager != nil {
		klet.probeManager = kubeDeps.ProbeManager
	} else {
		klet.probeManager = prober.NewManager(
			klet.statusManager,
			klet.livenessManager,
			klet.readinessManager,
			klet.startupManager,
			klet.runner,
			kubeDeps.Recorder)
	}

	var clusterTrustBundleManager clustertrustbundle.Manager = &clustertrustbundle.NoopManager{}
	if kubeDeps.KubeClient != nil && utilfeature.DefaultFeatureGate.Enabled(features.ClusterTrustBundleProjection) {
		clusterTrustBundleManager = clustertrustbundle.NewLazyInformerManager(ctx, kubeDeps.KubeClient, 2*int(kubeCfg.MaxPods))
		logger.Info("ClusterTrustBundle informer will be started eventually once a trust bundle is requested")
	} else {
		logger.Info("Not starting ClusterTrustBundle informer because we are in static kubelet mode or the ClusterTrustBundleProjection featuregate is disabled")
	}

	if kubeDeps.KubeClient != nil && utilfeature.DefaultFeatureGate.Enabled(features.PodCertificateRequest) {
		kubeInformers := informers.NewSharedInformerFactoryWithOptions(
			kubeDeps.KubeClient,
			0,
			informers.WithTweakListOptions(func(options *metav1.ListOptions) {
				options.FieldSelector = fields.OneTermEqualSelector("spec.nodeName", string(nodeName)).String()
			}),
		)
		podCertificateManager := podcertificate.NewIssuingManager(
			kubeDeps.KubeClient,
			klet.podManager,
			kubeDeps.Recorder,
			kubeInformers.Certificates().V1beta1().PodCertificateRequests(),
			nodeInformer,
			nodeName,
			clock.RealClock{},
		)
		klet.podCertificateManager = podCertificateManager
		kubeInformers.Start(ctx.Done())
		go podCertificateManager.Run(ctx)

		metrics.RegisterCollectors(collectors.PodCertificateCollectorFor(podCertificateManager))
	} else {
		klet.podCertificateManager = &podcertificate.NoOpManager{}
		logger.Info("Not starting PodCertificateRequest manager because we are in static kubelet mode or the PodCertificateProjection feature gate is disabled")
	}

	// NewInitializedVolumePluginMgr initializes some storageErrors on the Kubelet runtimeState (in csi_plugin.go init)
	// which affects node ready status. This function must be called before Kubelet is initialized so that the Node
	// ReadyState is accurate with the storage state.
	klet.volumePluginMgr, err = NewInitializedVolumePluginMgr(klet, secretManager, configMapManager, tokenManager, clusterTrustBundleManager, kubeDeps.VolumePlugins, kubeDeps.DynamicPluginProber)
	if err != nil {
		return nil, err
	}
	klet.pluginManager = pluginmanager.NewPluginManager(
		klet.getPluginsRegistrationDir(), /* sockDir */
		kubeDeps.Recorder,
	)

	// If the experimentalMounterPathFlag is set, we do not want to
	// check node capabilities since the mount path is not the default
	if len(experimentalMounterPath) != 0 {
		// Replace the nameserver in containerized-mounter's rootfs/etc/resolv.conf with kubelet.ClusterDNS
		// so that service name could be resolved
		klet.dnsConfigurer.SetupDNSinContainerizedMounter(logger, experimentalMounterPath)
	}

	// setup volumeManager
	klet.volumeManager = volumemanager.NewVolumeManager(
		kubeCfg.EnableControllerAttachDetach,
		nodeName,
		klet.podManager,
		klet.podWorkers,
		klet.kubeClient,
		klet.volumePluginMgr,
		kubeDeps.Mounter,
		kubeDeps.HostUtil,
		klet.getPodsDir(),
		kubeDeps.Recorder,
		volumepathhandler.NewBlockVolumePathHandler())

	boMax, base := newCrashLoopBackOff(kubeCfg)

	klet.crashLoopBackOff = flowcontrol.NewBackOff(base, boMax)
	klet.crashLoopBackOff.HasExpiredFunc = func(eventTime time.Time, lastUpdate time.Time, maxDuration time.Duration) bool {
		return eventTime.Sub(lastUpdate) > 600*time.Second
	}

	// setup eviction manager
	evictionManager, evictionAdmitHandler := eviction.NewManager(klet.resourceAnalyzer, evictionConfig,
		killPodNow(ctx, klet.podWorkers, kubeDeps.Recorder), klet.imageManager, klet.containerGC, kubeDeps.Recorder, nodeRef, klet.clock, kubeCfg.LocalStorageCapacityIsolation)

	klet.evictionManager = evictionManager
	handlers := []lifecycle.PodAdmitHandler{}
	handlers = append(handlers, evictionAdmitHandler)

	if utilfeature.DefaultFeatureGate.Enabled(features.NodeDeclaredFeatures) {
		if status, err := klet.containerRuntime.Status(ctx); err == nil && status != nil {
			klet.runtimeState.setRuntimeFeatures(status.Features)
		} else if err != nil {
			logger.V(4).Info("Unable to prefetch container runtime features for node declared features", "err", err)
		}
		v, err := versionutil.Parse(version.Get().String())
		if err != nil {
			return nil, fmt.Errorf("failed to parse version: %w", err)
		}
		framework := ndf.DefaultFramework
		klet.version = v
		klet.nodeDeclaredFeaturesFramework = framework
		klet.nodeDeclaredFeatures = klet.discoverNodeDeclaredFeatures()
		klet.nodeDeclaredFeaturesSet = framework.MustMapSorted(klet.nodeDeclaredFeatures)
	}

	// Safe, allowed sysctls can always be used as unsafe sysctls in the spec.
	// Hence, we concatenate those two lists.
	safeAndUnsafeSysctls := append(sysctl.SafeSysctlAllowlist(ctx), allowedUnsafeSysctls...)
	sysctlsAllowlist, err := sysctl.NewAllowlist(safeAndUnsafeSysctls)
	if err != nil {
		return nil, err
	}
	handlers = append(handlers, sysctlsAllowlist)

	// enable active deadline handler
	activeDeadlineHandler, err := newActiveDeadlineHandler(klet.statusManager, kubeDeps.Recorder, klet.clock)
	if err != nil {
		return nil, err
	}
	klet.AddPodSyncLoopHandler(activeDeadlineHandler)
	klet.AddPodSyncHandler(activeDeadlineHandler)

	handlers = append(handlers, klet.containerManager.GetAllocateResourcesPodAdmitHandler())

	criticalPodAdmissionHandler := preemption.NewCriticalPodAdmissionHandler(klet.getAllocatedPods, killPodNow(ctx, klet.podWorkers, kubeDeps.Recorder), kubeDeps.Recorder)
	handlers = append(handlers, lifecycle.NewPredicateAdmitHandler(klet.GetCachedNode, criticalPodAdmissionHandler, klet.containerManager.UpdatePluginResources))
	// apply functional Option's
	for _, opt := range kubeDeps.Options {
		opt(klet)
	}

	if goos == "linux" {
		// AppArmor is a Linux kernel security module and it does not support other operating systems.
		klet.appArmorValidator = apparmor.NewValidator()
		handlers = append(handlers, lifecycle.NewAppArmorAdmitHandler(klet.appArmorValidator))
	}

	handlers = append(handlers, lifecycle.NewPodFeaturesAdmitHandler())

	if utilfeature.DefaultFeatureGate.Enabled(features.NodeDeclaredFeatures) {
		handlers = append(handlers, lifecycle.NewDeclaredFeaturesAdmitHandler(klet.nodeDeclaredFeaturesFramework, klet.nodeDeclaredFeaturesSet, klet.version))
	}

	leaseDuration := time.Duration(kubeCfg.NodeLeaseDurationSeconds) * time.Second
	renewInterval := time.Duration(float64(leaseDuration) * nodeLeaseRenewIntervalFraction)
	klet.nodeLeaseController = lease.NewController(
		klet.clock,
		klet.heartbeatClient,
		string(klet.nodeName),
		kubeCfg.NodeLeaseDurationSeconds,
		klet.onRepeatedHeartbeatFailure,
		renewInterval,
		string(klet.nodeName),
		v1.NamespaceNodeLease,
		util.SetNodeOwnerFunc(ctx, klet.heartbeatClient, string(klet.nodeName)))

	// setup node shutdown manager
	shutdownManager := nodeshutdown.NewManager(&nodeshutdown.Config{
		Logger:                           logger,
		VolumeManager:                    klet.volumeManager,
		Recorder:                         kubeDeps.Recorder,
		NodeRef:                          nodeRef,
		GetPodsFunc:                      klet.GetActivePods,
		KillPodFunc:                      killPodNow(ctx, klet.podWorkers, kubeDeps.Recorder),
		SyncNodeStatusFunc:               klet.syncNodeStatus,
		ShutdownGracePeriodRequested:     kubeCfg.ShutdownGracePeriod.Duration,
		ShutdownGracePeriodCriticalPods:  kubeCfg.ShutdownGracePeriodCriticalPods.Duration,
		ShutdownGracePeriodByPodPriority: kubeCfg.ShutdownGracePeriodByPodPriority,
		StateDirectory:                   rootDirectory,
	})
	klet.shutdownManager = shutdownManager
	handlers = append(handlers, shutdownManager)

	klet.allocationManager.AddPodAdmitHandlers(append([]lifecycle.PodAdmitHandler{resizeAdmitHandler}, handlers...))

	var usernsIDsPerPod *int64
	if kubeCfg.UserNamespaces != nil {
		usernsIDsPerPod = kubeCfg.UserNamespaces.IDsPerPod
	}
	klet.usernsManager, err = userns.MakeUserNsManager(logger, klet, usernsIDsPerPod)
	if err != nil {
		return nil, fmt.Errorf("create user namespace manager: %w", err)
	}

	// Finally, put the most recent version of the config on the Kubelet, so
	// people can see how it was configured.
	klet.kubeletConfiguration = *kubeCfg

	// Generating the status funcs should be the last thing we do,
	// since this relies on the rest of the Kubelet having been constructed.
	klet.setNodeStatusFuncs = klet.defaultNodeStatusFuncs()

	return klet, nil
}

type serviceLister interface {
	List(labels.Selector) ([]*v1.Service, error)
}

// Kubelet is the main kubelet implementation.
type Kubelet struct {
	kubeletConfiguration kubeletconfiginternal.KubeletConfiguration

	// hostname is the hostname the kubelet detected or was given via flag/config
	hostname string

	nodeName        types.NodeName
	cachedNode      *v1.Node
	runtimeCache    kubecontainer.RuntimeCache
	kubeClient      clientset.Interface
	heartbeatClient clientset.Interface
	// mirrorPodClient is used to create and delete mirror pods in the API for static
	// pods.
	mirrorPodClient kubepod.MirrorClient

	rootDirectory    string
	podLogsDirectory string

	// onRepeatedHeartbeatFailure is called when a heartbeat operation fails more than once. optional.
	onRepeatedHeartbeatFailure func()

	// podManager stores the desired set of admitted pods and mirror pods that the kubelet should be
	// running. The actual set of running pods is stored on the podWorkers. The manager is populated
	// by the kubelet config loops which abstracts receiving configuration from many different sources
	// (api for regular pods, local filesystem or http for static pods). The manager may be consulted
	// by other components that need to see the set of desired pods. Note that not all desired pods are
	// running, and not all running pods are in the podManager - for instance, force deleting a pod
	// from the apiserver will remove it from the podManager, but the pod may still be terminating and
	// tracked by the podWorkers. Components that need to know the actual consumed resources of the
	// node or are driven by podWorkers and the sync*Pod methods (status, volume, stats) should also
	// consult the podWorkers when reconciling.
	//
	// TODO: review all kubelet components that need the actual set of pods (vs the desired set)
	// and update them to use podWorkers instead of podManager. This may introduce latency in some
	// methods, but avoids race conditions and correctly accounts for terminating pods that have
	// been force deleted or static pods that have been updated.
	// https://github.com/kubernetes/kubernetes/issues/116970
	podManager kubepod.Manager

	// podWorkers is responsible for driving the lifecycle state machine of each pod. The worker is
	// notified of config changes, updates, periodic reconciliation, container runtime updates, and
	// evictions of all desired pods and will invoke reconciliation methods per pod in separate
	// goroutines. The podWorkers are authoritative in the kubelet for what pods are actually being
	// run and their current state:
	//
	// * syncing: pod should be running (syncPod)
	// * terminating: pod should be stopped (syncTerminatingPod)
	// * terminated: pod should have all resources cleaned up (syncTerminatedPod)
	//
	// and invoke the handler methods that correspond to each state. Components within the
	// kubelet that need to know the phase of the pod in order to correctly set up or tear down
	// resources must consult the podWorkers.
	//
	// Once a pod has been accepted by the pod workers, no other pod with that same UID (and
	// name+namespace, for static pods) will be started until the first pod has fully terminated
	// and been cleaned up by SyncKnownPods. This means a pod may be desired (in API), admitted
	// (in pod manager), and requested (by invoking UpdatePod) but not start for an arbitrarily
	// long interval because a prior pod is still terminating.
	//
	// As an event-driven (by UpdatePod) controller, the podWorkers must periodically be resynced
	// by the kubelet invoking SyncKnownPods with the desired state (admitted pods in podManager).
	// Since the podManager may be unaware of some running pods due to force deletion, the
	// podWorkers are responsible for triggering a sync of pods that are no longer desired but
	// must still run to completion.
	podWorkers PodWorkers

	// evictionManager observes the state of the node for situations that could impact node stability
	// and evicts pods (sets to phase Failed with reason Evicted) to reduce resource pressure. The
	// eviction manager acts on the actual state of the node and considers the podWorker to be
	// authoritative.
	evictionManager eviction.Manager

	// probeManager tracks the set of running pods and ensures any user-defined periodic checks are
	// run to introspect the state of each pod.  The probe manager acts on the actual state of the node
	// and is notified of pods by the podWorker. The probe manager is the authoritative source of the
	// most recent probe status and is responsible for notifying the status manager, which
	// synthesizes them into the overall pod status.
	probeManager prober.Manager

	// secretManager caches the set of secrets used by running pods on this node. The podWorkers
	// notify the secretManager when pods are started and terminated, and the secretManager must
	// then keep the needed secrets up-to-date as they change.
	secretManager secret.Manager

	// configMapManager caches the set of config maps used by running pods on this node. The
	// podWorkers notify the configMapManager when pods are started and terminated, and the
	// configMapManager must then keep the needed config maps up-to-date as they change.
	configMapManager configmap.Manager

	// volumeManager observes the set of running pods and is responsible for attaching, mounting,
	// unmounting, and detaching as those pods move through their lifecycle. It periodically
	// synchronizes the set of known volumes to the set of actually desired volumes and cleans up
	// any orphaned volumes. The volume manager considers the podWorker to be authoritative for
	// which pods are running.
	volumeManager volumemanager.VolumeManager

	// statusManager receives updated pod status updates from the podWorker and updates the API
	// status of those pods to match. The statusManager is authoritative for the synthesized
	// status of the pod from the kubelet's perspective (other components own the individual
	// elements of status) and should be consulted by components in preference to assembling
	// that status themselves. Note that the status manager is downstream of the pod worker
	// and components that need to check whether a pod is still running should instead directly
	// consult the pod worker.
	statusManager status.Manager

	// allocationManager manages allocated resources for pods.
	allocationManager allocation.Manager

	// podCertificateManager is fed updates as pods are added and removed from
	// the node, and requests certificates for them based on their configured
	// pod certificate volumes.
	podCertificateManager podcertificate.Manager

	// resyncInterval is the interval between periodic full reconciliations of
	// pods on this node.
	resyncInterval time.Duration

	// sourcesReady records the sources seen by the kubelet, it is thread-safe.
	sourcesReady config.SourcesReady

	// Optional, defaults to /logs/ from /var/log
	logServer http.Handler
	// Optional, defaults to simple Docker implementation
	runner kubecontainer.CommandRunner

	// cAdvisor used for container information.
	cadvisor cadvisor.Interface

	// Set to true to have the node register itself with the apiserver.
	registerNode bool
	// List of taints to add to a node object when the kubelet registers itself.
	registerWithTaints []v1.Taint
	// for internal book keeping; access only from within registerWithApiserver
	registrationCompleted bool

	// dnsConfigurer is used for setting up DNS resolver configuration when launching pods.
	dnsConfigurer *dns.Configurer

	// serviceLister knows how to list services
	serviceLister serviceLister
	// serviceHasSynced indicates whether services have been sync'd at least once.
	// Check this before trusting a response from the lister.
	serviceHasSynced cache.InformerSynced
	// nodeLister knows how to list nodes
	nodeLister corelisters.NodeLister
	// nodeHasSynced indicates whether nodes have been sync'd at least once.
	// Check this before trusting a response from the node lister.
	nodeHasSynced cache.InformerSynced
	// a list of node labels to register
	nodeLabels map[string]string

	// nodeDeclaredFeatures is the ordered static list of features that are determined at startup and declared in node status.
	nodeDeclaredFeatures []string
	// nodeDeclaredFeaturesSet provides the same features as nodeDeclaredFeatures, but as a set for faster inference.
	nodeDeclaredFeaturesSet ndf.FeatureSet
	// nodeDeclaredFeaturesFramework provides the shared logic for feature discovery and pod requirement inference.
	nodeDeclaredFeaturesFramework *ndf.Framework

	// kubelet version
	version *versionutil.Version

	// Last timestamp when runtime responded on ping.
	// Mutex is used to protect this value.
	runtimeState *runtimeState

	// Volume plugins.
	volumePluginMgr *volume.VolumePluginMgr

	// Manages container health check results.
	livenessManager  proberesults.Manager
	readinessManager proberesults.Manager
	startupManager   proberesults.Manager

	// The EventRecorder to use
	recorder record.EventRecorderLogger

	// Policy for handling garbage collection of dead containers.
	containerGC kubecontainer.GC

	// Manager for image garbage collection.
	imageManager images.ImageGCManager

	// Manager for container logs.
	containerLogManager logs.ContainerLogManager

	// Cached MachineInfo returned by cadvisor.
	machineInfoLock sync.RWMutex
	machineInfo     *cadvisorapi.MachineInfo

	// Handles certificate rotations.
	serverCertificateManager certificate.Manager

	// handles reloading of ClientCA from the disk
	clientCAManager *dynamiccertificates.DynamicServingCertificateController

	// Indicates that the node initialization happens in an external cloud controller
	externalCloudProvider bool
	// Reference to this node.
	nodeRef *v1.ObjectReference

	// Container runtime.
	containerRuntime kubecontainer.Runtime

	// Streaming runtime handles container streaming.
	streamingRuntime kubecontainer.StreamingRuntime

	// Container runtime service (needed by container runtime Start()).
	runtimeService internalapi.RuntimeService

	// reasonCache caches the failure reason of the last creation of all containers, which is
	// used for generating ContainerStatus.
	reasonCache *ReasonCache

	// containerRuntimeReadyExpected indicates whether container runtime being ready is expected
	// so errors are logged without verbosity guard, to avoid excessive error logs at node startup.
	// It's false during the node initialization period of nodeReadyGracePeriod, and after that
	// it's set to true by fastStatusUpdateOnce when it exits.
	containerRuntimeReadyExpected bool

	// nodeStatusUpdateFrequency specifies how often kubelet computes node status. If node lease
	// feature is not enabled, it is also the frequency that kubelet posts node status to master.
	// In that case, be cautious when changing the constant, it must work with nodeMonitorGracePeriod
	// in nodecontroller. There are several constraints:
	// 1. nodeMonitorGracePeriod must be N times more than nodeStatusUpdateFrequency, where
	//    N means number of retries allowed for kubelet to post node status. It is pointless
	//    to make nodeMonitorGracePeriod be less than nodeStatusUpdateFrequency, since there
	//    will only be fresh values from Kubelet at an interval of nodeStatusUpdateFrequency.
	//    The constant must be less than podEvictionTimeout.
	// 2. nodeStatusUpdateFrequency needs to be large enough for kubelet to generate node
	//    status. Kubelet may fail to update node status reliably if the value is too small,
	//    as it takes time to gather all necessary node information.
	nodeStatusUpdateFrequency time.Duration

	// nodeStatusReportFrequency is the frequency that kubelet posts node
	// status to master. It is only used when node lease feature is enabled.
	nodeStatusReportFrequency time.Duration

	// delayAfterNodeStatusChange is the one-time random duration that we add to the next node status report interval
	// every time when there's an actual node status change or kubelet restart. But all future node status update that
	// is not caused by real status change will stick with nodeStatusReportFrequency. The random duration is a uniform
	// distribution over [-0.5*nodeStatusReportFrequency, 0.5*nodeStatusReportFrequency]
	delayAfterNodeStatusChange time.Duration

	// lastStatusReportTime is the time when node status was last reported.
	lastStatusReportTime time.Time

	// syncNodeStatusMux is a lock on updating the node status, because this path is not thread-safe.
	// This lock is used by Kubelet.syncNodeStatus and Kubelet.fastNodeStatusUpdate functions and shouldn't be used anywhere else.
	syncNodeStatusMux sync.Mutex

	// updatePodCIDRMux is a lock on updating pod CIDR, because this path is not thread-safe.
	// This lock is used by Kubelet.updatePodCIDR function and shouldn't be used anywhere else.
	updatePodCIDRMux sync.Mutex

	// updateRuntimeMux is a lock on updating runtime, because this path is not thread-safe.
	// This lock is used by Kubelet.updateRuntimeUp, Kubelet.fastNodeStatusUpdate and
	// Kubelet.HandlerSupportsUserNamespaces functions and shouldn't be used anywhere else.
	updateRuntimeMux sync.Mutex

	// nodeLeaseController claims and renews the node lease for this Kubelet
	nodeLeaseController lease.Controller

	// pleg observes the state of the container runtime and notifies the kubelet of changes to containers, which
	// notifies the podWorkers to reconcile the state of the pod (for instance, if a container dies and needs to
	// be restarted).
	pleg pleg.PodLifecycleEventGenerator

	// eventedPleg supplements the pleg to deliver edge-driven container changes with low-latency.
	eventedPleg pleg.PodLifecycleEventGenerator

	// Store kubecontainer.PodStatus for all pods.
	podCache kubecontainer.ROCache

	// os is a facade for various syscalls that need to be mocked during testing.
	os kubecontainer.OSInterface

	// Watcher of out of memory events.
	oomWatcher oomwatcher.Watcher

	// Monitor resource usage
	resourceAnalyzer serverstats.ResourceAnalyzer

	// Whether or not we should have the QOS cgroup hierarchy for resource management
	cgroupsPerQOS bool

	// If non-empty, pass this to the container runtime as the root cgroup.
	cgroupRoot string

	// Mounter to use for volumes.
	mounter mount.Interface

	// hostutil to interact with filesystems
	hostutil hostutil.HostUtils

	// subpather to execute subpath actions
	subpather subpath.Interface

	// Manager of non-Runtime containers.
	containerManager cm.ContainerManager

	// Maximum Number of Pods which can be run by this Kubelet
	maxPods int

	// Monitor Kubelet's sync loop
	syncLoopMonitor atomic.Value

	// Container restart Backoff
	crashLoopBackOff *flowcontrol.Backoff

	// Information about the ports which are opened by daemons on Node running this Kubelet server.
	daemonEndpoints *v1.NodeDaemonEndpoints

	// A queue used to trigger pod workers.
	workQueue queue.WorkQueue

	// oneTimeInitializer is used to initialize modules that are dependent on the runtime to be up.
	oneTimeInitializer sync.Once

	// If set, use this IP address or addresses for the node
	nodeIPs []net.IP

	// use this function to validate the kubelet nodeIP
	nodeIPValidator func(net.IP) error

	// If non-nil, this is a unique identifier for the node in an external database, eg. cloudprovider
	providerID string

	// clock is an interface that provides time related functionality in a way that makes it
	// easy to test the code.
	clock clock.WithTicker

	// handlers called during the tryUpdateNodeStatus cycle
	setNodeStatusFuncs []func(context.Context, *v1.Node) error

	lastNodeUnschedulableLock sync.Mutex
	// maintains Node.Spec.Unschedulable value from previous run of tryUpdateNodeStatus()
	lastNodeUnschedulable bool

	// the list of handlers to call during pod sync loop.
	lifecycle.PodSyncLoopHandlers

	// the list of handlers to call during pod sync.
	lifecycle.PodSyncHandlers

	// the number of allowed pods per core
	podsPerCore int

	// enableControllerAttachDetach indicates the Attach/Detach controller
	// should manage attachment/detachment of volumes scheduled to this node,
	// and disable kubelet from executing any attach/detach operations
	enableControllerAttachDetach bool

	// trigger deleting containers in a pod
	containerDeletor *podContainerDeletor

	// config iptables util rules
	makeIPTablesUtilChains bool

	// The AppArmor validator for checking whether AppArmor is supported.
	appArmorValidator apparmor.Validator

	// StatsProvider provides the node and the container stats.
	StatsProvider *stats.Provider

	// pluginmanager runs a set of asynchronous loops that figure out which
	// plugins need to be registered/unregistered based on this node and makes it so.
	pluginManager pluginmanager.PluginManager

	// This flag sets a maximum number of images to report in the node status.
	nodeStatusMaxImages int32

	// Handles RuntimeClass objects for the Kubelet.
	runtimeClassManager *runtimeclass.Manager

	// Handles node shutdown events for the Node.
	shutdownManager nodeshutdown.Manager

	// Manage user namespaces
	usernsManager *userns.UsernsManager

	// OpenTelemetry Tracer
	tracer trace.Tracer

	// Track node startup latencies
	nodeStartupLatencyTracker util.NodeStartupLatencyTracker

	// Track pod startup latencies
	podStartupLatencyTracker util.PodStartupLatencyTracker

	// Health check kubelet
	healthChecker watchdog.HealthChecker

	// flagz is the Reader interface to get flags for flagz page.
	flagz flagz.Reader

	// podsServer is the server that provides the pods gRPC service.
	podsServer *pods.PodsServer
}

// ListPodStats is delegated to StatsProvider, which implements stats.Provider interface
func (kl *Kubelet) ListPodStats(ctx context.Context) ([]statsapi.PodStats, error) {
	return kl.StatsProvider.ListPodStats(ctx)
}

// ListPodCPUAndMemoryStats is delegated to StatsProvider, which implements stats.Provider interface
func (kl *Kubelet) ListPodCPUAndMemoryStats(ctx context.Context) ([]statsapi.PodStats, error) {
	return kl.StatsProvider.ListPodCPUAndMemoryStats(ctx)
}

// PodCPUAndMemoryStats is delegated to StatsProvider
func (kl *Kubelet) PodCPUAndMemoryStats(ctx context.Context, pod *v1.Pod, podStatus *kubecontainer.PodStatus) (*statsapi.PodStats, error) {
	return kl.StatsProvider.PodCPUAndMemoryStats(ctx, pod, podStatus)
}

// ListPodStatsAndUpdateCPUNanoCoreUsage is delegated to StatsProvider, which implements stats.Provider interface
func (kl *Kubelet) ListPodStatsAndUpdateCPUNanoCoreUsage(ctx context.Context) ([]statsapi.PodStats, error) {
	return kl.StatsProvider.ListPodStatsAndUpdateCPUNanoCoreUsage(ctx)
}

// ImageFsStats is delegated to StatsProvider, which implements stats.Provider interface
func (kl *Kubelet) ImageFsStats(ctx context.Context) (*statsapi.FsStats, *statsapi.FsStats, error) {
	return kl.StatsProvider.ImageFsStats(ctx)
}

// GetCgroupStats is delegated to StatsProvider, which implements stats.Provider interface
func (kl *Kubelet) GetCgroupStats(cgroupName string, updateStats bool) (*statsapi.ContainerStats, *statsapi.NetworkStats, error) {
	return kl.StatsProvider.GetCgroupStats(cgroupName, updateStats)
}

// GetCgroupCPUAndMemoryStats is delegated to StatsProvider, which implements stats.Provider interface
func (kl *Kubelet) GetCgroupCPUAndMemoryStats(cgroupName string, updateStats bool) (*statsapi.ContainerStats, error) {
	return kl.StatsProvider.GetCgroupCPUAndMemoryStats(cgroupName, updateStats)
}

// RootFsStats is delegated to StatsProvider, which implements stats.Provider interface
func (kl *Kubelet) RootFsStats() (*statsapi.FsStats, error) {
	return kl.StatsProvider.RootFsStats()
}

// RlimitStats is delegated to StatsProvider, which implements stats.Provider interface
func (kl *Kubelet) RlimitStats() (*statsapi.RlimitStats, error) {
	return kl.StatsProvider.RlimitStats()
}

// setupDataDirs creates:
// 1.  the root directory
// 2.  the pods directory
// 3.  the plugins directory
// 4.  the pod-resources directory
// 5.  the checkpoint directory
// 6.  the pod logs root directory
func (kl *Kubelet) setupDataDirs(logger klog.Logger) error {
	if cleanedRoot := filepath.Clean(kl.rootDirectory); cleanedRoot != kl.rootDirectory {
		return fmt.Errorf("rootDirectory not in canonical form: expected %s, was %s", cleanedRoot, kl.rootDirectory)
	}
	pluginRegistrationDir := kl.getPluginsRegistrationDir()
	pluginsDir := kl.getPluginsDir()
	if err := os.MkdirAll(kl.getRootDir(), 0750); err != nil {
		return fmt.Errorf("error creating root directory: %v", err)
	}
	if err := utilfs.MkdirAll(kl.getPodLogsDir(), 0750); err != nil {
		return fmt.Errorf("error creating pod logs root directory %q: %w", kl.getPodLogsDir(), err)
	}
	if err := kl.hostutil.MakeRShared(kl.getRootDir()); err != nil {
		return fmt.Errorf("error configuring root directory: %v", err)
	}
	if err := os.MkdirAll(kl.getPodsDir(), 0750); err != nil {
		return fmt.Errorf("error creating pods directory: %v", err)
	}
	if err := utilfs.MkdirAll(kl.getPluginsDir(), 0750); err != nil {
		return fmt.Errorf("error creating plugins directory: %v", err)
	}
	if err := utilfs.MkdirAll(kl.getPluginsRegistrationDir(), 0750); err != nil {
		return fmt.Errorf("error creating plugins registry directory: %v", err)
	}
	if err := os.MkdirAll(kl.getPodResourcesDir(), 0750); err != nil {
		return fmt.Errorf("error creating podresources directory: %v", err)
	}
	if utilfeature.DefaultFeatureGate.Enabled(features.ContainerCheckpoint) {
		if err := utilfs.MkdirAll(kl.getCheckpointsDir(), 0700); err != nil {
			return fmt.Errorf("error creating checkpoint directory: %v", err)
		}
	}
	if selinux.GetEnabled() {
		err := selinux.SetFileLabel(pluginRegistrationDir, kubeletconfig.KubeletPluginsDirSELinuxLabel)
		if err != nil {
			logger.Info("Unprivileged containerized plugins might not work, could not set selinux context on plugin registration dir", "path", pluginRegistrationDir, "err", err)
		}
		err = selinux.SetFileLabel(pluginsDir, kubeletconfig.KubeletPluginsDirSELinuxLabel)
		if err != nil {
			logger.Info("Unprivileged containerized plugins might not work, could not set selinux context on plugins dir", "path", pluginsDir, "err", err)
		}
	}
	return nil
}

// StartGarbageCollection starts garbage collection threads.
func (kl *Kubelet) StartGarbageCollection(ctx context.Context) {
	logger := klog.FromContext(ctx)
	loggedContainerGCFailure := false
	go wait.Until(func() {
		if err := kl.containerGC.GarbageCollect(ctx); err != nil {
			logger.Error(err, "Container garbage collection failed")
			kl.recorder.WithLogger(logger).Eventf(kl.nodeRef, v1.EventTypeWarning, events.ContainerGCFailed, "%s", err.Error())
			loggedContainerGCFailure = true
		} else {
			var vLevel klog.Level = 4
			if loggedContainerGCFailure {
				vLevel = 1
				loggedContainerGCFailure = false
			}

			logger.V(int(vLevel)).Info("Container garbage collection succeeded")
		}
	}, ContainerGCPeriod, wait.NeverStop)

	// when the high threshold is set to 100, and the max age is 0 (or the max age feature is disabled)
	// stub the image GC manager
	if kl.kubeletConfiguration.ImageGCHighThresholdPercent == 100 && kl.kubeletConfiguration.ImageMaximumGCAge.Duration == 0 {
		logger.V(2).Info("ImageGCHighThresholdPercent is set 100 and ImageMaximumGCAge is 0, Disable image GC")
		return
	}

	prevImageGCFailed := false
	beganGC := time.Now()
	go wait.Until(func() {
		if err := kl.imageManager.GarbageCollect(ctx, beganGC); err != nil {
			if prevImageGCFailed {
				logger.Error(err, "Image garbage collection failed multiple times in a row")
				// Only create an event for repeated failures
				kl.recorder.WithLogger(logger).Event(kl.nodeRef, v1.EventTypeWarning, events.ImageGCFailed, err.Error())
			} else {
				logger.Error(err, "Image garbage collection failed once. Stats initialization may not have completed yet")
			}
			prevImageGCFailed = true
		} else {
			var vLevel klog.Level = 4
			if prevImageGCFailed {
				vLevel = 1
				prevImageGCFailed = false
			}

			logger.V(int(vLevel)).Info("Image garbage collection succeeded")
		}
	}, ImageGCPeriod, wait.NeverStop)
}

// initializeModules will initialize internal modules that do not require the container runtime to be up.
// Note that the modules here must not depend on modules that are not initialized here.
func (kl *Kubelet) initializeModules(ctx context.Context) error {
	logger := klog.FromContext(ctx)
	// Prometheus metrics.
	metrics.Register()
	metrics.RegisterCollectors(
		collectors.NewVolumeStatsCollector(kl),
		collectors.NewLogMetricsCollector(kl.StatsProvider.ListPodStats),
	)
	metrics.SetNodeName(kl.nodeName)
	servermetrics.Register()

	// Setup filesystem directories.
	if err := kl.setupDataDirs(logger); err != nil {
		return err
	}

	// If the container logs directory does not exist, create it.
	if _, err := os.Stat(ContainerLogsDir); err != nil {
		if err := kl.os.MkdirAll(ContainerLogsDir, 0755); err != nil {
			return fmt.Errorf("failed to create directory %q: %v", ContainerLogsDir, err)
		}
	}

	if goos == "windows" {
		// On Windows we should not allow other users to read the logs directory
		// to avoid allowing non-root containers from reading the logs of other containers.
		if err := utilfs.Chmod(ContainerLogsDir, 0750); err != nil {
			return fmt.Errorf("failed to set permissions on directory %q: %w", ContainerLogsDir, err)
		}
	}

	// Start the image manager.
	kl.imageManager.Start(ctx)

	// Start the certificate manager if it was enabled.
	if kl.serverCertificateManager != nil {
		kl.serverCertificateManager.Start()
	}

	// Start the client CA manager if it was enabled.
	if kl.clientCAManager != nil {
		go kl.clientCAManager.Run(1, ctx.Done())
	}

	// Start out of memory watcher.
	if kl.oomWatcher != nil {
		if err := kl.oomWatcher.Start(ctx, kl.nodeRef); err != nil {
			return fmt.Errorf("failed to start OOM watcher: %w", err)
		}
	}

	// Start resource analyzer
	kl.resourceAnalyzer.Start(ctx)

	return nil
}

// initializeRuntimeDependentModules will initialize internal modules that require the container runtime to be up.
func (kl *Kubelet) initializeRuntimeDependentModules(ctx context.Context) {
	logger := klog.FromContext(ctx)
	if err := kl.cadvisor.Start(); err != nil {
		// Fail kubelet and rely on the babysitter to retry starting kubelet.
		logger.Error(err, "Failed to start cAdvisor")
		os.Exit(1)
	}

	// trigger on-demand stats collection once so that we have capacity information for ephemeral storage.
	// ignore any errors, since if stats collection is not successful, the container manager will fail to start below.
	kl.StatsProvider.GetCgroupStats("/", true)
	// Start container manager.
	node, err := kl.getNodeAnyWay(ctx)
	if err != nil {
		// Fail kubelet and rely on the babysitter to retry starting kubelet.
		logger.Error(err, "Kubelet failed to get node info")
		os.Exit(1)
	}
	// containerManager must start after cAdvisor because it needs filesystem capacity information
	if err := kl.containerManager.Start(ctx, node, kl.GetActivePods, kl.getNodeAnyWay, kl.sourcesReady, kl.statusManager, kl.runtimeService, kl.supportLocalStorageCapacityIsolation()); err != nil {
		// Fail kubelet and rely on the babysitter to retry starting kubelet.
		logger.Error(err, "Failed to start ContainerManager")
		os.Exit(1)
	}
	// eviction manager must start after cadvisor because it needs to know if the container runtime has a dedicated imagefs
	// Eviction decisions are based on the allocated (rather than desired) pod resources.
	kl.evictionManager.Start(ctx, kl.StatsProvider, kl.getAllocatedPods, kl.PodIsFinished, evictionMonitoringPeriod)

	// container log manager must start after container runtime is up to retrieve information from container runtime
	// and inform container to reopen log file after log rotation.
	kl.containerLogManager.Start(ctx)
	// Adding Registration Callback function for CSI Driver
	kl.pluginManager.AddHandler(pluginwatcherapi.CSIPlugin, plugincache.PluginHandler(csi.PluginHandler))
	// Adding Registration Callback function for DRA Plugin and Device Plugin
	for name, handler := range kl.containerManager.GetPluginRegistrationHandlers() {
		kl.pluginManager.AddHandler(name, handler)
	}

	// Start the plugin manager
	logger.V(4).Info("Starting plugin manager")
	go kl.pluginManager.Run(ctx, kl.sourcesReady, wait.NeverStop)

	err = kl.shutdownManager.Start(ctx)
	if err != nil {
		// The shutdown manager is not critical for kubelet, so log failure, but don't block Kubelet startup if there was a failure starting it.
		logger.Error(err, "Failed to start node shutdown manager")
	}
}

// Run starts the kubelet reacting to config updates
func (kl *Kubelet) Run(ctx context.Context, updates <-chan kubetypes.PodUpdate) {
	logger := klog.FromContext(ctx)
	if kl.logServer == nil {
		file := http.FileServer(http.Dir(nodeLogDir))
		if utilfeature.DefaultFeatureGate.Enabled(features.NodeLogQuery) && kl.kubeletConfiguration.EnableSystemLogQuery {
			kl.logServer = http.StripPrefix("/logs/", http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
				if nlq, errs := newNodeLogQuery(req.URL.Query()); len(errs) > 0 {
					http.Error(w, errs.ToAggregate().Error(), http.StatusBadRequest)
					return
				} else if nlq != nil {
					if req.URL.Path != "/" && req.URL.Path != "" {
						http.Error(w, "path not allowed in query mode", http.StatusNotAcceptable)
						return
					}
					if errs := nlq.validate(); len(errs) > 0 {
						http.Error(w, errs.ToAggregate().Error(), http.StatusNotAcceptable)
						return
					}
					// Validation ensures that the request does not query services and files at the same time
					if len(nlq.Services) > 0 {
						journal.ServeHTTP(w, req)
						return
					}
					// Validation ensures that the request does not explicitly query multiple files at the same time
					if len(nlq.Files) == 1 {
						// Account for the \ being used on Windows clients
						req.URL.Path = filepath.ToSlash(nlq.Files[0])
					}
				}
				// Fall back in case the caller is directly trying to query a file
				// Example: kubectl get --raw /api/v1/nodes/$name/proxy/logs/foo.log
				file.ServeHTTP(w, req)
			}))
		} else {
			kl.logServer = http.StripPrefix("/logs/", file)
		}
	}
	if kl.kubeClient == nil {
		logger.Info("No API server defined - no node status update will be sent")
	}

	if err := kl.initializeModules(ctx); err != nil {
		kl.recorder.WithLogger(logger).Eventf(kl.nodeRef, v1.EventTypeWarning, events.KubeletSetupFailed, "%s", err.Error())
		logger.Error(err, "Failed to initialize internal modules")
		os.Exit(1)
	}

	if err := kl.cgroupVersionCheck(); err != nil {
		logger.V(2).Info("Warning: cgroup check", "error", err)
	}

	// Start the allocation manager
	if kl.allocationManager != nil {
		kl.allocationManager.Run(ctx)
	}

	// Start volume manager
	go kl.volumeManager.Run(ctx, kl.sourcesReady)

	if kl.kubeClient != nil {
		// Start two go-routines to update the status.
		//
		// The first will report to the apiserver every nodeStatusUpdateFrequency and is aimed to provide regular status intervals,
		// while the second is used to provide a more timely status update during initialization and runs an one-shot update to the apiserver
		// once the node becomes ready, then exits afterwards.
		//
		// Introduce some small jittering to ensure that over time the requests won't start
		// accumulating at approximately the same time from the set of nodes due to priority and
		// fairness effect.
		go func() {
			// Call updateRuntimeUp once before syncNodeStatus to make sure kubelet had already checked runtime state
			// otherwise when restart kubelet, syncNodeStatus will report node notReady in first report period
			kl.updateRuntimeUp(ctx)
			wait.JitterUntil(func() { kl.syncNodeStatus(ctx) }, kl.nodeStatusUpdateFrequency, 0.04, true, wait.NeverStop)
		}()

		go kl.fastStatusUpdateOnce()

		// Keep renewing the node lease until the kubelet exits.
		// This intentionally does not use the kubelet context so lease renewal can
		// continue during graceful shutdown.
		go kl.nodeLeaseController.Run(context.Background())

		// Mirror pods for static pods may not be created immediately during node startup
		// due to node registration or informer sync delays. They will be created eventually
		//  when static pods are resynced (every 1-1.5 minutes).
		// To ensure kube-scheduler is aware of static pod resource usage faster,
		// mirror pods are created as soon as the node registers.
		go kl.fastStaticPodsRegistration(ctx)
	}
	go wait.UntilWithContext(ctx, kl.updateRuntimeUp, 5*time.Second)

	// Set up iptables util rules
	if kl.makeIPTablesUtilChains {
		kl.initNetworkUtil(logger)
	}

	// Start component sync loops.
	kl.statusManager.Start(ctx)

	// Start syncing RuntimeClasses if enabled.
	if kl.runtimeClassManager != nil {
		kl.runtimeClassManager.Start(wait.NeverStop)
	}

	// Start the pod lifecycle event generator.
	kl.pleg.Start()

	// Start eventedPLEG only if EventedPLEG feature gate is enabled.
	if utilfeature.DefaultFeatureGate.Enabled(features.EventedPLEG) {
		kl.eventedPleg.Start()
	}

	if kl.healthChecker != nil {
		kl.healthChecker.SetHealthCheckers(kl, kl.containerManager.GetHealthCheckers())
	}

	kl.syncLoop(ctx, updates, kl)
}

// SyncPod is the transaction script for the sync of a single pod (setting up)
// a pod. This method is reentrant and expected to converge a pod towards the
// desired state of the spec. The reverse (teardown) is handled in
// SyncTerminatingPod and SyncTerminatedPod. If SyncPod exits without error,
// then the pod runtime state is in sync with the desired configuration state
// (pod is running). If SyncPod exits with a transient error, the next
// invocation of SyncPod is expected to make progress towards reaching the
// desired state. SyncPod exits with isTerminal when the pod was detected to
// have reached a terminal lifecycle phase due to container exits (for
// RestartNever or RestartOnFailure) and the next method invoked will be
// SyncTerminatingPod. If the pod terminates for any other reason, SyncPod
// will receive a context cancellation and should exit as soon as possible.
//
// Arguments:
//
// updateType - whether this is a create (first time) or an update, should
// only be used for metrics since this method must be reentrant
//
// pod - the pod that is being set up
//
// mirrorPod - the mirror pod known to the kubelet for this pod, if any
//
// podStatus - the most recent pod status observed for this pod which can
// be used to determine the set of actions that should be taken during
// this loop of SyncPod
//
// The workflow is:
//   - If the pod is being created, record pod worker start latency
//   - Call generateAPIPodStatus to prepare an v1.PodStatus for the pod
//   - If the pod is being seen as running for the first time, record pod
//     start latency
//   - Update the status of the pod in the status manager
//   - Stop the pod's containers if it should not be running due to soft
//     admission
//   - Ensure any background tracking for a runnable pod is started
//   - Create a mirror pod if the pod is a static pod, and does not
//     already have a mirror pod
//   - Create the data directories for the pod if they do not exist
//   - Wait for volumes to attach/mount
//   - Fetch the pull secrets for the pod
//   - Call the container runtime's SyncPod callback
//   - Update the traffic shaping for the pod's ingress and egress limits
//
// If any step of this workflow errors, the error is returned, and is repeated
// on the next SyncPod call.
//
// This operation writes all events that are dispatched in order to provide
// the most accurate information possible about an error situation to aid debugging.
// Callers should not write an event if this operation returns an error.
func (kl *Kubelet) SyncPod(ctx context.Context, updateType kubetypes.SyncPodType, pod, mirrorPod *v1.Pod, podStatus *kubecontainer.PodStatus) (isTerminal bool, postSync func(), err error) {
	ctx, otelSpan := kl.tracer.Start(ctx, "syncPod", trace.WithAttributes(
		semconv.K8SPodUIDKey.String(string(pod.UID)),
		attribute.String("k8s.pod", klog.KObj(pod).String()),
		semconv.K8SPodNameKey.String(pod.Name),
		attribute.String("k8s.pod.update_type", updateType.String()),
		semconv.K8SNamespaceNameKey.String(pod.Namespace),
	))
	logger := klog.FromContext(ctx)
	logger.V(4).Info("SyncPod enter", "pod", klog.KObj(pod), "podUID", pod.UID)
	defer func() {
		if err != nil {
			otelSpan.RecordError(err)
			otelSpan.SetStatus(codes.Error, err.Error())
		}
		logger.V(4).Info("SyncPod exit", "pod", klog.KObj(pod), "podUID", pod.UID, "isTerminal", isTerminal)
		otelSpan.End()
	}()

	// Latency measurements for the main workflow are relative to the
	// first time the pod was seen by kubelet.
	var firstSeenTime time.Time
	if firstSeenTimeStr, ok := pod.Annotations[kubetypes.ConfigFirstSeenAnnotationKey]; ok {
		firstSeenTime = kubetypes.ConvertToTimestamp(firstSeenTimeStr).Get()
	}

	// Record pod worker start latency if being created
	// TODO: make pod workers record their own latencies
	if updateType == kubetypes.SyncPodCreate {
		if !firstSeenTime.IsZero() {
			// This is the first time we are syncing the pod. Record the latency
			// since kubelet first saw the pod if firstSeenTime is set.
			metrics.PodWorkerStartDuration.Observe(metrics.SinceInSeconds(firstSeenTime))
		} else {
			logger.V(3).Info("First seen time not recorded for pod",
				"podUID", pod.UID,
				"pod", klog.KObj(pod))
		}
	}

	if utilfeature.DefaultFeatureGate.Enabled(features.InPlacePodVerticalScaling) {
		// Check whether a resize is in progress so we can set the PodResizeInProgressCondition accordingly.
		if kl.containerRuntime.IsPodResizeInProgress(pod, podStatus) {
			kl.statusManager.SetPodResizeInProgressCondition(pod.UID, "", "", pod.Generation)
		} else if generation, cleared := kl.statusManager.ClearPodResizeInProgressCondition(pod.UID); cleared {
			// (Allocated == Actual) => clear the resize in-progress status.
			msg := events.PodResizeCompletedMsg(logger, pod, generation)
			kl.recorder.WithLogger(logger).Eventf(pod, v1.EventTypeNormal, events.ResizeCompleted, "%s", msg)
		}
		// TODO(natasha41575): There is a race condition here, where the goroutine in the
		// allocation manager may allocate a new resize and unconditionally set the
		// PodResizeInProgressCondition before we set the status below.
	}

	// Generate final API pod status with pod and status manager status
	apiPodStatus := kl.generateAPIPodStatus(ctx, pod, podStatus, false)
	// The pod IP may be changed in generateAPIPodStatus if the pod is using host network. (See #24576)
	// TODO(random-liu): After writing pod spec into container labels, check whether pod is using host network, and
	// set pod IP to hostIP directly in runtime.GetPodStatus
	podStatus.IPs = make([]string, 0, len(apiPodStatus.PodIPs))
	for _, ipInfo := range apiPodStatus.PodIPs {
		podStatus.IPs = append(podStatus.IPs, ipInfo.IP)
	}
	if len(podStatus.IPs) == 0 && len(apiPodStatus.PodIP) > 0 {
		podStatus.IPs = []string{apiPodStatus.PodIP}
	}

	// If the pod is terminal, we don't need to continue to setup the pod
	if apiPodStatus.Phase == v1.PodSucceeded || apiPodStatus.Phase == v1.PodFailed {
		kl.statusManager.SetPodStatus(logger, pod, apiPodStatus)
		isTerminal = true
		return isTerminal, nil, nil
	}

	// Record the time it takes for the pod to become running
	// since kubelet first saw the pod if firstSeenTime is set.
	existingStatus, ok := kl.statusManager.GetPodStatus(pod.UID)
	if !ok || existingStatus.Phase == v1.PodPending && apiPodStatus.Phase == v1.PodRunning &&
		!firstSeenTime.IsZero() {
		metrics.PodStartDuration.Observe(metrics.SinceInSeconds(firstSeenTime))
	}

	kl.statusManager.SetPodStatus(logger, pod, apiPodStatus)

	// If the network plugin is not ready, only start the pod if it uses the host network
	if err := kl.runtimeState.networkErrors(); err != nil && !kubecontainer.IsHostNetworkPod(pod) {
		kl.recorder.WithLogger(logger).Eventf(pod, v1.EventTypeWarning, events.NetworkNotReady, "%s: %v", NetworkNotReadyErrorMsg, err)
		return false, nil, fmt.Errorf("%s: %v", NetworkNotReadyErrorMsg, err)
	}

	// ensure the kubelet knows about referenced secrets or configmaps used by the pod
	if !kl.podWorkers.IsPodTerminationRequested(pod.UID) {
		if kl.secretManager != nil {
			kl.secretManager.RegisterPod(pod)
		}
		if kl.configMapManager != nil {
			kl.configMapManager.RegisterPod(pod)
		}
	}

	// Create Cgroups for the pod and apply resource parameters
	// to them if cgroups-per-qos flag is enabled.
	pcm := kl.containerManager.NewPodContainerManager()
	// If pod has already been terminated then we need not create
	// or update the pod's cgroup
	// TODO: once context cancellation is added this check can be removed
	if !kl.podWorkers.IsPodTerminationRequested(pod.UID) {
		// When the kubelet is restarted with the cgroups-per-qos
		// flag enabled, all the pod's running containers
		// should be killed intermittently and brought back up
		// under the qos cgroup hierarchy.
		// Check if this is the pod's first sync
		firstSync := true
		for _, containerStatus := range apiPodStatus.ContainerStatuses {
			if containerStatus.State.Running != nil {
				firstSync = false
				break
			}
		}
		// Don't kill containers in pod if pod's cgroups already
		// exists or the pod is running for the first time
		podKilled := false
		if !pcm.Exists(pod) && !firstSync {
			p := kubecontainer.ConvertPodStatusToRunningPod(kl.getRuntime().Type(), podStatus)
			if err := kl.killPod(ctx, pod, p, nil); err == nil {
				podKilled = true
			} else {
				if wait.Interrupted(err) {
					return false, nil, nil
				}
				logger.Error(err, "KillPod failed", "pod", klog.KObj(pod), "podStatus", podStatus)
			}
		}
		// Create and Update pod's Cgroups
		// Don't create cgroups for run once pod if it was killed above
		// The current policy is not to restart the run once pods when
		// the kubelet is restarted with the new flag as run once pods are
		// expected to run only once and if the kubelet is restarted then
		// they are not expected to run again.
		// We don't create and apply updates to cgroup if its a run once pod and was killed above
		runOnce := pod.Spec.RestartPolicy == v1.RestartPolicyNever
		// With ContainerRestartRules, if any container is restartable, the pod should be restarted.
		if utilfeature.DefaultFeatureGate.Enabled(features.ContainerRestartRules) {
			for _, c := range pod.Spec.Containers {
				if podutil.IsContainerRestartable(pod.Spec, c) {
					runOnce = false
				}
			}
		}
		if !podKilled || !runOnce {
			if !pcm.Exists(pod) {
				if err := kl.containerManager.UpdateQOSCgroups(logger); err != nil {
					logger.V(2).Info("Failed to update QoS cgroups while syncing pod", "pod", klog.KObj(pod), "err", err)
				}
				if err := pcm.EnsureExists(logger, pod); err != nil {
					kl.recorder.WithLogger(logger).Eventf(pod, v1.EventTypeWarning, events.FailedToCreatePodContainer, "unable to ensure pod container exists: %v", err)
					return false, nil, fmt.Errorf("failed to ensure that the pod: %v cgroups exist and are correctly applied: %v", pod.UID, err)
				}

				if err = kl.containerRuntime.UpdateActuatedPodLevelResources(pod); err != nil {
					return false, nil, fmt.Errorf("failed to update the state of pod-level resources for the pod %v : %w", pod.UID, err)
				}
			}
		}
	}

	// Create Mirror Pod for Static Pod if it doesn't already exist
	kl.tryReconcileMirrorPods(ctx, pod, mirrorPod)

	// Make data directories for the pod
	if err := kl.makePodDataDirs(pod); err != nil {
		kl.recorder.WithLogger(logger).Eventf(pod, v1.EventTypeWarning, events.FailedToMakePodDataDirectories, "error making pod data directories: %v", err)
		logger.Error(err, "Unable to make pod data directories for pod", "pod", klog.KObj(pod))
		return false, nil, err
	}

	// Wait for volumes to attach/mount
	if err := kl.volumeManager.WaitForAttachAndMount(ctx, pod); err != nil {
		var volumeAttachLimitErr *volumemanager.VolumeAttachLimitExceededError
		if errors.As(err, &volumeAttachLimitErr) {
			kl.rejectPod(ctx, pod, volumemanager.VolumeAttachmentLimitExceededReason, volumeAttachLimitErr.Error())
			recordAdmissionRejection(volumemanager.VolumeAttachmentLimitExceededReason)
			return true, nil, nil
		}
		if !wait.Interrupted(err) {
			kl.recorder.WithLogger(logger).Eventf(pod, v1.EventTypeWarning, events.FailedMountVolume, "Unable to attach or mount volumes: %v", err)
			logger.Error(err, "Unable to attach or mount volumes for pod; skipping pod", "pod", klog.KObj(pod))
		}
		return false, nil, err
	}

	// Fetch the pull secrets for the pod
	pullSecrets := kl.getPullSecretsForPod(logger, pod)

	// Ensure the pod is being probed
	kl.probeManager.AddPod(ctx, pod)

	// TODO(#113606): use cancellation from the incoming context parameter, which comes from the pod worker.
	// Currently, using cancellation from that context causes test failures. To remove this WithoutCancel,
	// any wait.Interrupted errors need to be filtered from result and bypass the reasonCache - cancelling
	// the context for SyncPod is a known and deliberate error, not a generic error.
	// Use WithoutCancel instead of a new context.TODO() to propagate trace context
	// Call the container runtime's SyncPod callback
	sctx := context.WithoutCancel(ctx)
	restartingAllContainers := false
	if utilfeature.DefaultFeatureGate.Enabled(features.RestartAllContainersOnContainerExits) {
		for _, cond := range apiPodStatus.Conditions {
			if cond.Type == v1.AllContainersRestarting && cond.Status == v1.ConditionTrue {
				restartingAllContainers = true
			}
		}
	}
	result := kl.containerRuntime.SyncPod(sctx, pod, podStatus, pullSecrets, kl.crashLoopBackOff, restartingAllContainers)
	kl.reasonCache.Update(pod.UID, result)

	// If we just performed a RestartAllContainers reset, we want to immediately
	// trigger another sync to start the containers, rather than waiting for PLEG
	// or the periodic resync.
	if utilfeature.DefaultFeatureGate.Enabled(features.RestartAllContainersOnContainerExits) &&
		restartingAllContainers && result.Error() == nil {
		shouldRequeue := false
		for _, r := range result.SyncResults {
			if r.Action == kubecontainer.RemoveContainer && r.Error == nil {
				shouldRequeue = true
				break
			}
		}
		if shouldRequeue {
			// This will not cause an infinite loop because UpdatePod merges concurrent updates
			// to the same pod. Because all containers are removed, the subsequent SyncPod
			// execution will unset the AllContainersRestarting condition and break the cycle.
			kl.podWorkers.UpdatePod(ctx, UpdatePodOptions{
				Pod:        pod,
				MirrorPod:  mirrorPod,
				UpdateType: kubetypes.SyncPodUpdate,
			})
		}
	}

	if utilfeature.DefaultFeatureGate.Enabled(features.InPlacePodVerticalScaling) {
		for _, r := range result.SyncResults {
			if r.Action == kubecontainer.ResizePodInPlace && r.Error != nil {
				// If the condition already exists, the observedGeneration does not get updated.
				if generation, updated := kl.statusManager.SetPodResizeInProgressCondition(pod.UID, v1.PodReasonError, r.Message, pod.Generation); updated {
					msg := events.PodResizeErrorMsg(logger, pod, generation, r.Message)
					kl.recorder.WithLogger(logger).Eventf(pod, v1.EventTypeWarning, events.ResizeError, "%s", msg)
				}
			}
		}
	}

	err = result.Error()
	if len(result.SyncResults) > 0 && err == nil {
		postSync = func() {
			kl.RequestPodRelist(pod.UID)
		}
	}

	return false, postSync, err
}

// SyncTerminatingPod is expected to terminate all running containers in a pod. Once this method
// returns without error, the pod is considered to be terminated and it will be safe to clean up any
// pod state that is tied to the lifetime of running containers. The next method invoked will be
// SyncTerminatedPod. This method is expected to return with the grace period provided and the
// provided context may be cancelled if the duration is exceeded. The method may also be interrupted
// with a context cancellation if the grace period is shortened by the user or the kubelet (such as
// during eviction). This method is not guaranteed to be called if a pod is force deleted from the
// configuration and the kubelet is restarted - SyncTerminatingRuntimePod handles those orphaned
// pods.
func (kl *Kubelet) SyncTerminatingPod(ctx context.Context, pod *v1.Pod, podStatus *kubecontainer.PodStatus, gracePeriod *int64, podStatusFn func(*v1.PodStatus)) (err error) {
	// TODO(#113606): connect this with the incoming context parameter, which comes from the pod worker.
	// Currently, using that context causes test failures.
	logger := klog.FromContext(ctx)
	ctx = klog.NewContext(context.TODO(), logger)
	logger.V(4).Info("SyncTerminatingPod enter", "pod", klog.KObj(pod), "podUID", pod.UID)

	ctx, otelSpan := kl.tracer.Start(ctx, "syncTerminatingPod", trace.WithAttributes(
		semconv.K8SPodUIDKey.String(string(pod.UID)),
		attribute.String("k8s.pod", klog.KObj(pod).String()),
		semconv.K8SPodNameKey.String(pod.Name),
		semconv.K8SNamespaceNameKey.String(pod.Namespace),
	))
	defer func() {
		if err != nil {
			otelSpan.RecordError(err)
			otelSpan.SetStatus(codes.Error, err.Error())
		}
		otelSpan.End()
		logger.V(4).Info("SyncTerminatingPod exit", "pod", klog.KObj(pod), "podUID", pod.UID)
	}()

	apiPodStatus := kl.generateAPIPodStatus(ctx, pod, podStatus, false)
	if podStatusFn != nil {
		podStatusFn(&apiPodStatus)
	}
	kl.statusManager.SetPodStatus(logger, pod, apiPodStatus)

	if gracePeriod != nil {
		logger.V(4).Info("Pod terminating with grace period", "pod", klog.KObj(pod), "podUID", pod.UID, "gracePeriod", *gracePeriod)
	} else {
		logger.V(4).Info("Pod terminating with grace period", "pod", klog.KObj(pod), "podUID", pod.UID, "gracePeriod", nil)
	}

	kl.probeManager.StopLivenessAndStartup(pod)

	p := kubecontainer.ConvertPodStatusToRunningPod(kl.getRuntime().Type(), podStatus)
	if err := kl.killPod(ctx, pod, p, gracePeriod); err != nil {
		kl.recorder.WithLogger(logger).Eventf(pod, v1.EventTypeWarning, events.FailedToKillPod, "error killing pod: %v", err)
		// there was an error killing the pod, so we return that error directly
		return fmt.Errorf("error killing terminating pod: %w", err)
	}

	// Once the containers are stopped, we can stop probing for liveness and readiness.
	// TODO: once a pod is terminal, certain probes (liveness exec) could be stopped immediately after
	//   the detection of a container shutdown or (for readiness) after the first failure. Tracked as
	//   https://github.com/kubernetes/kubernetes/issues/107894 although may not be worth optimizing.
	kl.probeManager.RemovePod(pod)

	// Guard against consistency issues in KillPod implementations by checking that there are no
	// running containers. This method is invoked infrequently so this is effectively free and can
	// catch race conditions introduced by callers updating pod status out of order.
	// TODO: have KillPod return the terminal status of stopped containers and write that into the
	//  cache immediately
	runtimePod, err := kl.containerRuntime.GetPod(ctx, pod.UID)
	if err != nil {
		if errors.Is(err, kubecontainer.ErrPodNotFound) {
			// If pod sandboxes were already cleaned up, proceed with an empty runtimePod.
			runtimePod = &kubecontainer.Pod{
				ID:        pod.UID,
				Name:      pod.Name,
				Namespace: pod.Namespace,
				Timestamp: kl.clock.Now(),
			}
		} else {
			return fmt.Errorf("unable to get pod prior to final pod termination: %w", err)
		}
	}
	stoppedPodStatus, err := kl.containerRuntime.GetPodStatus(ctx, runtimePod)
	if err != nil {
		return fmt.Errorf("unable to read pod status prior t

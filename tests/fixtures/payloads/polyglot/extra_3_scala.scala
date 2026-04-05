/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.apache.spark

import java.io._
import java.net.URI
import java.util.{Arrays, Locale, Properties, ServiceLoader, UUID}
import java.util.concurrent.{ConcurrentHashMap, ConcurrentMap}
import java.util.concurrent.atomic.{AtomicBoolean, AtomicInteger, AtomicReference}

import scala.collection.Map
import scala.collection.concurrent.{Map => ScalaConcurrentMap}
import scala.collection.immutable
import scala.collection.mutable.HashMap
import scala.concurrent.{Future, Promise}
import scala.jdk.CollectionConverters._
import scala.reflect.{classTag, ClassTag}
import scala.util.control.NonFatal

import com.google.common.collect.MapMaker
import org.apache.hadoop.conf.Configuration
import org.apache.hadoop.fs.{FileSystem, Path}
import org.apache.hadoop.io.{BooleanWritable, BytesWritable, DoubleWritable, FloatWritable, IntWritable, LongWritable, NullWritable, Text, Writable}
import org.apache.hadoop.mapred.{FileInputFormat, InputFormat, JobConf, SequenceFileInputFormat, TextInputFormat}
import org.apache.hadoop.mapreduce.{InputFormat => NewInputFormat, Job => NewHadoopJob}
import org.apache.hadoop.mapreduce.lib.input.{FileInputFormat => NewFileInputFormat}

import org.apache.spark.annotation.{DeveloperApi, Experimental}
import org.apache.spark.broadcast.Broadcast
import org.apache.spark.deploy.{LocalSparkCluster, SparkHadoopUtil}
import org.apache.spark.errors.SparkCoreErrors
import org.apache.spark.executor.{Executor, ExecutorMetrics, ExecutorMetricsSource}
import org.apache.spark.input.{FixedLengthBinaryInputFormat, PortableDataStream, StreamInputFormat, WholeTextFileInputFormat}
import org.apache.spark.internal.Logging
import org.apache.spark.internal.LogKeys
import org.apache.spark.internal.config._
import org.apache.spark.internal.config.Tests._
import org.apache.spark.internal.config.UI._
import org.apache.spark.internal.plugin.PluginContainer
import org.apache.spark.io.CompressionCodec
import org.apache.spark.launcher.{JavaModuleOptions, SparkLauncher}
import org.apache.spark.metrics.source.JVMCPUSource
import org.apache.spark.partial.{ApproximateEvaluator, PartialResult}
import org.apache.spark.rdd._
import org.apache.spark.resource._
import org.apache.spark.resource.ResourceUtils._
import org.apache.spark.rpc.RpcEndpointRef
import org.apache.spark.scheduler._
import org.apache.spark.scheduler.cluster.StandaloneSchedulerBackend
import org.apache.spark.scheduler.local.LocalSchedulerBackend
import org.apache.spark.shuffle.ShuffleDataIOUtils
import org.apache.spark.shuffle.api.ShuffleDriverComponents
import org.apache.spark.status.{AppStatusSource, AppStatusStore}
import org.apache.spark.status.api.v1.ThreadStackTrace
import org.apache.spark.storage._
import org.apache.spark.storage.BlockManagerMessages.{TriggerHeapHistogram, TriggerThreadDump}
import org.apache.spark.ui.{ConsoleProgressBar, SparkUI}
import org.apache.spark.util._
import org.apache.spark.util.ArrayImplicits._
import org.apache.spark.util.logging.DriverLogger

/**
 * Main entry point for Spark functionality. A SparkContext represents the connection to a Spark
 * cluster, and can be used to create RDDs, accumulators and broadcast variables on that cluster.
 *
 * @note Only one `SparkContext` should be active per JVM. You must `stop()` the
 *   active `SparkContext` before creating a new one.
 * @param config a Spark Config object describing the application configuration. Any settings in
 *   this config overrides the default configs as well as system properties.
 */
class SparkContext(config: SparkConf) extends Logging {

  // The call site where this SparkContext was constructed.
  private val creationSite: CallSite = Utils.getCallSite()

  private var stopSite: Option[CallSite] = None

  if (!config.get(EXECUTOR_ALLOW_SPARK_CONTEXT)) {
    // In order to prevent SparkContext from being created in executors.
    SparkContext.assertOnDriver()
  }

  // In order to prevent multiple SparkContexts from being active at the same time, mark this
  // context as having started construction.
  // NOTE: this must be placed at the beginning of the SparkContext constructor.
  SparkContext.markPartiallyConstructed(this)

  val startTime = System.currentTimeMillis()

  private[spark] val stopped: AtomicBoolean = new AtomicBoolean(false)

  private[spark] def assertNotStopped(): Unit = {
    if (stopped.get()) {
      val activeContext = SparkContext.activeContext.get()
      val activeCreationSite =
        if (activeContext == null) {
          "(No active SparkContext.)"
        } else {
          activeContext.creationSite.longForm
        }
      throw new IllegalStateException(
        s"""Cannot call methods on a stopped SparkContext.
           |This stopped SparkContext was created at:
           |
           |${creationSite.longForm}
           |
           |And it was stopped at:
           |
           |${stopSite.getOrElse(CallSite.empty).longForm}
           |
           |The currently active SparkContext was created at:
           |
           |$activeCreationSite
         """.stripMargin)
    }
  }

  /**
   * Create a SparkContext that loads settings from system properties (for instance, when
   * launching with ./bin/spark-submit).
   */
  def this() = this(new SparkConf())

  /**
   * Alternative constructor that allows setting common Spark properties directly
   *
   * @param master Cluster URL to connect to (e.g. spark://host:port, local[4]).
   * @param appName A name for your application, to display on the cluster web UI
   * @param conf a [[org.apache.spark.SparkConf]] object specifying other Spark parameters
   */
  def this(master: String, appName: String, conf: SparkConf) =
    this(SparkContext.updatedConf(conf, master, appName))

  /**
   * Alternative constructor that allows setting common Spark properties directly
   *
   * @param master Cluster URL to connect to (e.g. spark://host:port, local[4]).
   * @param appName A name for your application, to display on the cluster web UI.
   * @param sparkHome Location where Spark is installed on cluster nodes.
   * @param jars Collection of JARs to send to the cluster. These can be paths on the local file
   *             system or HDFS, HTTP, HTTPS, or FTP URLs.
   * @param environment Environment variables to set on worker nodes.
   */
  def this(
      master: String,
      appName: String,
      sparkHome: String = null,
      jars: Seq[String] = Nil,
      environment: Map[String, String] = Map()) = {
    this(SparkContext.updatedConf(new SparkConf(), master, appName, sparkHome, jars, environment))
  }

  // The following constructors are required when Java code accesses SparkContext directly.
  // Please see SI-4278

  /**
   * Alternative constructor that allows setting common Spark properties directly
   *
   * @param master Cluster URL to connect to (e.g. spark://host:port, local[4]).
   * @param appName A name for your application, to display on the cluster web UI.
   */
  private[spark] def this(master: String, appName: String) =
    this(master, appName, null, Nil, Map())

  /**
   * Alternative constructor that allows setting common Spark properties directly
   *
   * @param master Cluster URL to connect to (e.g. spark://host:port, local[4]).
   * @param appName A name for your application, to display on the cluster web UI.
   * @param sparkHome Location where Spark is installed on cluster nodes.
   */
  private[spark] def this(master: String, appName: String, sparkHome: String) =
    this(master, appName, sparkHome, Nil, Map())

  /**
   * Alternative constructor that allows setting common Spark properties directly
   *
   * @param master Cluster URL to connect to (e.g. spark://host:port, local[4]).
   * @param appName A name for your application, to display on the cluster web UI.
   * @param sparkHome Location where Spark is installed on cluster nodes.
   * @param jars Collection of JARs to send to the cluster. These can be paths on the local file
   *             system or HDFS, HTTP, HTTPS, or FTP URLs.
   */
  private[spark] def this(master: String, appName: String, sparkHome: String, jars: Seq[String]) =
    this(master, appName, sparkHome, jars, Map())

  // log out Spark Version in Spark driver log
  logInfo(log"Running Spark version ${MDC(LogKeys.SPARK_VERSION, SPARK_VERSION)}")
  logInfo(log"OS info ${MDC(LogKeys.OS_NAME, Utils.osName)}," +
    log" ${MDC(LogKeys.OS_VERSION, Utils.osVersion)}, " +
    log"${MDC(LogKeys.OS_ARCH, Utils.osArch)}")
  logInfo(log"Java version ${MDC(LogKeys.JAVA_VERSION, Utils.javaVersion)}")

  /* ------------------------------------------------------------------------------------- *
   | Private variables. These variables keep the internal state of the context, and are    |
   | not accessible by the outside world. They're mutable since we want to initialize all  |
   | of them to some neutral value ahead of time, so that calling "stop()" while the       |
   | constructor is still running is safe.                                                 |
   * ------------------------------------------------------------------------------------- */

  private var _conf: SparkConf = _
  private var _eventLogDir: Option[URI] = None
  private var _eventLogCodec: Option[String] = None
  private var _listenerBus: LiveListenerBus = _
  private var _env: SparkEnv = _
  private var _statusTracker: SparkStatusTracker = _
  private var _progressBar: Option[ConsoleProgressBar] = None
  private var _ui: Option[SparkUI] = None
  private var _hadoopConfiguration: Configuration = _
  private var _executorMemory: Int = _
  private var _schedulerBackend: SchedulerBackend = _
  private var _taskScheduler: TaskScheduler = _
  private var _heartbeatReceiver: RpcEndpointRef = _
  @volatile private var _dagScheduler: DAGScheduler = _
  private var _applicationId: String = _
  private var _applicationAttemptId: Option[String] = None
  private var _eventLogger: Option[EventLoggingListener] = None
  private var _driverLogger: Option[DriverLogger] = None
  private var _executorAllocationManager: Option[ExecutorAllocationManager] = None
  private var _cleaner: Option[ContextCleaner] = None
  private var _listenerBusStarted: Boolean = false
  private var _jars: Seq[String] = _
  private var _files: Seq[String] = _
  private var _archives: Seq[String] = _
  private var _shutdownHookRef: AnyRef = _
  private var _statusStore: AppStatusStore = _
  private var _heartbeater: Heartbeater = _
  private var _resources: immutable.Map[String, ResourceInformation] = _
  private var _shuffleDriverComponents: ShuffleDriverComponents = _
  private var _plugins: Option[PluginContainer] = None
  private var _resourceProfileManager: ResourceProfileManager = _

  /* ------------------------------------------------------------------------------------- *
   | Accessors and public fields. These provide access to the internal state of the        |
   | context.                                                                              |
   * ------------------------------------------------------------------------------------- */

  private[spark] def conf: SparkConf = _conf

  /** Get a read-only reference to the spark conf. This is preferred version over [[getConf]]. */
  def getReadOnlyConf: ReadOnlySparkConf = _conf

  /**
   * Return a copy of this SparkContext's configuration. The configuration ''cannot'' be
   * changed at runtime.
   */
  def getConf: SparkConf = conf.clone()

  def resources: Map[String, ResourceInformation] = _resources

  def jars: Seq[String] = _jars
  def files: Seq[String] = _files
  def archives: Seq[String] = _archives
  def master: String = _conf.get("spark.master")
  def deployMode: String = _conf.get(SUBMIT_DEPLOY_MODE)
  def appName: String = _conf.get("spark.app.name")

  private[spark] def isEventLogEnabled: Boolean = _conf.get(EVENT_LOG_ENABLED)
  private[spark] def eventLogDir: Option[URI] = _eventLogDir
  private[spark] def eventLogCodec: Option[String] = _eventLogCodec

  def isLocal: Boolean = Utils.isLocalMaster(_conf)

  /**
   * @return true if context is stopped or in the midst of stopping.
   */
  def isStopped: Boolean = stopped.get()

  private[spark] def statusStore: AppStatusStore = _statusStore

  // An asynchronous listener bus for Spark events
  private[spark] def listenerBus: LiveListenerBus = _listenerBus

  // This function allows components created by SparkEnv to be mocked in unit tests:
  private[spark] def createSparkEnv(
      conf: SparkConf,
      isLocal: Boolean,
      listenerBus: LiveListenerBus): SparkEnv = {
    SparkEnv.createDriverEnv(conf, isLocal, listenerBus, SparkContext.numDriverCores(master, conf))
  }

  private[spark] def env: SparkEnv = _env

  // Used to store session UUID with a URL for each static file/jar together and
  // the file's local timestamp. It's session uuid -> (URL -> timestamp).
  private[spark] val addedFiles = new ConcurrentHashMap[
    String, ScalaConcurrentMap[String, Long]]().asScala
  private[spark] val addedArchives = new ConcurrentHashMap[
    String, ScalaConcurrentMap[String, Long]]().asScala
  private[spark] val addedJars = new ConcurrentHashMap[
    String, ScalaConcurrentMap[String, Long]]().asScala

  private[spark] def allAddedFiles = addedFiles.values.flatten.toMap
  private[spark] def allAddedArchives = addedArchives.values.flatten.toMap
  private[spark] def allAddedJars = addedJars.values.flatten.toMap

  // Keeps track of all persisted RDDs
  private[spark] val persistentRdds = {
    val map: ConcurrentMap[Int, RDD[_]] = new MapMaker().weakValues().makeMap[Int, RDD[_]]()
    map.asScala
  }
  def statusTracker: SparkStatusTracker = _statusTracker

  private[spark] def progressBar: Option[ConsoleProgressBar] = _progressBar

  private[spark] def ui: Option[SparkUI] = _ui

  def uiWebUrl: Option[String] = _ui.map(_.webUrl)

  /**
   * A default Hadoop Configuration for the Hadoop code (e.g. file systems) that we reuse.
   *
   * @note As it will be reused in all Hadoop RDDs, it's better not to modify it unless you
   * plan to set some global configurations for all Hadoop RDDs.
   */
  def hadoopConfiguration: Configuration = _hadoopConfiguration

  private[spark] def executorMemory: Int = _executorMemory

  // Environment variables to pass to our executors.
  private[spark] val executorEnvs = HashMap[String, String]()

  // Set SPARK_USER for user who is running SparkContext.
  val sparkUser = Utils.getCurrentUserName()

  private[spark] def schedulerBackend: SchedulerBackend = _schedulerBackend

  private[spark] def taskScheduler: TaskScheduler = _taskScheduler
  private[spark] def taskScheduler_=(ts: TaskScheduler): Unit = {
    _taskScheduler = ts
  }

  private[spark] def dagScheduler: DAGScheduler = _dagScheduler
  private[spark] def dagScheduler_=(ds: DAGScheduler): Unit = {
    _dagScheduler = ds
  }

  private[spark] def shuffleDriverComponents: ShuffleDriverComponents = _shuffleDriverComponents

  /**
   * A unique identifier for the Spark application.
   * Its format depends on the scheduler implementation.
   * (i.e.
   *  in case of local spark app something like 'local-1433865536131'
   *  in case of YARN something like 'application_1433865536131_34483'
   * )
   */
  def applicationId: String = _applicationId
  def applicationAttemptId: Option[String] = _applicationAttemptId

  private[spark] def eventLogger: Option[EventLoggingListener] = _eventLogger

  private[spark] def executorAllocationManager: Option[ExecutorAllocationManager] =
    _executorAllocationManager

  private[spark] def resourceProfileManager: ResourceProfileManager = _resourceProfileManager

  private[spark] def cleaner: Option[ContextCleaner] = _cleaner

  private[spark] var checkpointDir: Option[String] = None

  // Thread Local variable that can be used by users to pass information down the stack
  protected[spark] val localProperties = new InheritableThreadLocal[Properties] {
    override def childValue(parent: Properties): Properties = {
      // Note: make a clone such that changes in the parent properties aren't reflected in
      // the those of the children threads, which has confusing semantics (SPARK-10563).
      Utils.cloneProperties(parent)
    }
    override protected def initialValue(): Properties = new Properties()
  }

  /* ------------------------------------------------------------------------------------- *
   | Initialization. This code initializes the context in a manner that is exception-safe. |
   | All internal fields holding state are initialized here, and any error prompts the     |
   | stop() method to be called.                                                           |
   * ------------------------------------------------------------------------------------- */

  /** Control our logLevel. This overrides any user-defined log settings.
   * @param logLevel The desired log level as a string.
   * Valid log levels include: ALL, DEBUG, ERROR, FATAL, INFO, OFF, TRACE, WARN
   */
  def setLogLevel(logLevel: String): Unit = {
    // let's allow lowercase or mixed case too
    val upperCased = logLevel.toUpperCase(Locale.ROOT)
    require(SparkContext.VALID_LOG_LEVELS.contains(upperCased),
      s"Supplied level $logLevel did not match one of:" +
        s" ${SparkContext.VALID_LOG_LEVELS.mkString(",")}")
    Utils.setLogLevelIfNeeded(upperCased)
    if (conf.get(EXECUTOR_ALLOW_SYNC_LOG_LEVEL) && _schedulerBackend != null) {
      _schedulerBackend.updateExecutorsLogLevel(upperCased)
    }
  }

  try {
    _conf = config.clone()
    _conf.get(SPARK_LOG_LEVEL).foreach { level =>
      if (Logging.setLogLevelPrinted) {
        System.err.printf("Setting Spark log level to \"%s\".\n", level)
      }
      setLogLevel(level)
    }
    _conf.validateSettings()
    _conf.set("spark.app.startTime", startTime.toString)

    if (!_conf.contains("spark.master")) {
      throw new SparkException("A master URL must be set in your configuration")
    }
    if (!_conf.contains("spark.app.name")) {
      throw new SparkException("An application name must be set in your configuration")
    }
    // HADOOP-19229 Vector IO on cloud storage: increase threshold for range merging
    // We can remove this after Apache Hadoop 3.4.2 releases
    conf.setIfMissing("spark.hadoop.fs.s3a.vectored.read.min.seek.size", "128K")
    conf.setIfMissing("spark.hadoop.fs.s3a.vectored.read.max.merged.size", "2M")
    // This should be set as early as possible.
    SparkContext.enableMagicCommitterIfNeeded(_conf)

    SparkContext.supplementJavaModuleOptions(_conf)
    SparkContext.supplementJavaIPv6Options(_conf)

    _driverLogger = DriverLogger(_conf)

    val resourcesFileOpt = conf.get(DRIVER_RESOURCES_FILE)
    _resources = getOrDiscoverAllResources(_conf, SPARK_DRIVER_PREFIX, resourcesFileOpt)
    logResourceInfo(SPARK_DRIVER_PREFIX, _resources)

    // log out spark.app.name in the Spark driver logs
    logInfo(log"Submitted application: ${MDC(LogKeys.APP_NAME, appName)}")

    // System property spark.yarn.app.id must be set if user code ran by AM on a YARN cluster
    if (master == "yarn" && deployMode == "cluster" && !_conf.contains("spark.yarn.app.id")) {
      throw new SparkException("Detected yarn cluster mode, but isn't running on a cluster. " +
        "Deployment to YARN is not supported directly by SparkContext. Please use spark-submit.")
    }

    if (_conf.getBoolean("spark.logConf", false)) {
      logInfo(log"Spark configuration:\n${MDC(LogKeys.CONFIG, _conf.toDebugString)}")
    }

    // Set Spark driver host and port system properties. This explicitly sets the configuration
    // instead of relying on the default value of the config constant.
    if (SparkMasterRegex.isK8s(master) &&
        _conf.getBoolean("spark.kubernetes.executor.useDriverPodIP", false)) {
      logInfo("Use DRIVER_BIND_ADDRESS instead of DRIVER_HOST_ADDRESS as driver address " +
        "because spark.kubernetes.executor.useDriverPodIP is true in K8s mode.")
      _conf.set(DRIVER_HOST_ADDRESS, _conf.get(DRIVER_BIND_ADDRESS))
    } else {
      _conf.set(DRIVER_HOST_ADDRESS, _conf.get(DRIVER_HOST_ADDRESS))
    }
    _conf.setIfMissing(DRIVER_PORT, 0)

    _conf.set(EXECUTOR_ID, SparkContext.DRIVER_IDENTIFIER)

    _jars = Utils.getUserJars(_conf)
    _files = _conf.getOption(FILES.key).map(_.split(",")).map(_.filter(_.nonEmpty))
      .toSeq.flatten
    _archives = _conf.getOption(ARCHIVES.key).map(Utils.stringToSeq).toSeq.flatten

    _eventLogDir =
      if (isEventLogEnabled) {
        val unresolvedDir = conf.get(EVENT_LOG_DIR).stripSuffix("/")
        Some(Utils.resolveURI(unresolvedDir))
      } else {
        None
      }

    _eventLogCodec = {
      val compress = _conf.get(EVENT_LOG_COMPRESS) &&
          !_conf.get(EVENT_LOG_COMPRESSION_CODEC).equalsIgnoreCase("none")
      if (compress && isEventLogEnabled) {
        Some(_conf.get(EVENT_LOG_COMPRESSION_CODEC)).map(CompressionCodec.getShortName)
      } else {
        None
      }
    }

    _listenerBus = new LiveListenerBus(_conf)

    // Initialize the app status store and listener before SparkEnv is created so that it gets
    // all events.
    val appStatusSource = AppStatusSource.createSource(conf)
    _statusStore = AppStatusStore.createLiveStore(conf, appStatusSource)
    listenerBus.addToStatusQueue(_statusStore.listener.get)

    // Create the Spark execution environment (cache, map output tracker, etc)
    _env = createSparkEnv(_conf, isLocal, listenerBus)
    SparkEnv.set(_env)

    // If running the REPL, register the repl's output dir with the file server.
    _conf.getOption("spark.repl.class.outputDir").foreach { path =>
      val replUri = _env.rpcEnv.fileServer.addDirectory("/classes", new File(path))
      _conf.set("spark.repl.class.uri", replUri)
    }

    _statusTracker = new SparkStatusTracker(this, _statusStore)

    _progressBar =
      if (_conf.get(UI_SHOW_CONSOLE_PROGRESS)) {
        Some(new ConsoleProgressBar(this))
      } else {
        None
      }

    _ui =
      if (conf.get(UI_ENABLED)) {
        Some(SparkUI.create(Some(this), _statusStore, _conf, _env.securityManager, appName, "",
          startTime))
      } else {
        // For tests, do not enable the UI
        None
      }
    // Bind the UI before starting the task scheduler to communicate
    // the bound port to the cluster manager properly
    _ui.foreach(_.bind())

    _hadoopConfiguration = SparkHadoopUtil.get.newConfiguration(_conf)
    // Performance optimization: this dummy call to .size() triggers eager evaluation of
    // Configuration's internal  `properties` field, guaranteeing that it will be computed and
    // cached before SessionState.newHadoopConf() uses `sc.hadoopConfiguration` to create
    // a new per-session Configuration. If `properties` has not been computed by that time
    // then each newly-created Configuration will perform its own expensive IO and XML
    // parsing to load configuration defaults and populate its own properties. By ensuring
    // that we've pre-computed the parent's properties, the child Configuration will simply
    // clone the parent's properties.
    _hadoopConfiguration.size()

    // Add each JAR given through the constructor
    if (jars != null) {
      jars.foreach(jar => addJar(jar, true))
      if (allAddedJars.nonEmpty) {
        _conf.set("spark.app.initial.jar.urls", allAddedJars.keys.toSeq.mkString(","))
      }
    }

    if (files != null) {
      files.foreach(file => addFile(file, false, true))
      if (allAddedFiles.nonEmpty) {
        _conf.set("spark.app.initial.file.urls", allAddedFiles.keys.toSeq.mkString(","))
      }
    }

    if (archives != null) {
      archives.foreach(file => addFile(file, false, true, isArchive = true))
      if (allAddedArchives.nonEmpty) {
        _conf.set("spark.app.initial.archive.urls", allAddedArchives.keys.toSeq.mkString(","))
      }
    }

    _executorMemory = SparkContext.executorMemoryInMb(_conf)

    // Convert java options to env vars as a work around
    // since we can't set env vars directly in sbt.
    for { (envKey, propKey) <- Seq(("SPARK_TESTING", IS_TESTING.key))
      value <- Option(System.getenv(envKey)).orElse(Option(System.getProperty(propKey)))} {
      executorEnvs(envKey) = value
    }
    Option(System.getenv("SPARK_PREPEND_CLASSES")).foreach { v =>
      executorEnvs("SPARK_PREPEND_CLASSES") = v
    }
    executorEnvs ++= _conf.getExecutorEnv
    executorEnvs("SPARK_USER") = sparkUser

    if (_conf.getOption("spark.executorEnv.OMP_NUM_THREADS").isEmpty) {
      // if OMP_NUM_THREADS is not explicitly set, override it with the value of "spark.task.cpus"
      // SPARK-41188: limit the thread number for OpenBLAS routine to the number of cores assigned
      // to this executor because some spark ML algorithms calls OpenBlAS via netlib-java
      // SPARK-28843: limit the OpenMP thread pool to the number of cores assigned to this executor
      // this avoids high memory consumption with pandas/numpy because of a large OpenMP thread pool
      // see https://github.com/numpy/numpy/issues/10455
      executorEnvs.put("OMP_NUM_THREADS", _conf.get("spark.task.cpus", "1"))
    }

    // We need to register "HeartbeatReceiver" before "createTaskScheduler" because Executor will
    // retrieve "HeartbeatReceiver" in the constructor. (SPARK-6640)
    _heartbeatReceiver = env.rpcEnv.setupEndpoint(
      HeartbeatReceiver.ENDPOINT_NAME, new HeartbeatReceiver(this))

    // Initialize any plugins before initializing the task scheduler and resource profile manager.
    _plugins = PluginContainer(this, _resources.asJava)
    _resourceProfileManager = new ResourceProfileManager(_conf, _listenerBus)
    _env.initializeShuffleManager()
    _env.initializeMemoryManager(SparkContext.numDriverCores(master, conf))

    // Create and start the scheduler
    val (sched, ts) = SparkContext.createTaskScheduler(this, master)
    _schedulerBackend = sched
    _taskScheduler = ts
    _dagScheduler = new DAGScheduler(this)
    _heartbeatReceiver.ask[Boolean](TaskSchedulerIsSet)

    if (_conf.get(EXECUTOR_ALLOW_SYNC_LOG_LEVEL)) {
      _conf.get(SPARK_LOG_LEVEL)
        .foreach(logLevel => _schedulerBackend.updateExecutorsLogLevel(logLevel))
    }

    _conf.get(CHECKPOINT_DIR).foreach(setCheckpointDir)

    val _executorMetricsSource =
      if (_conf.get(METRICS_EXECUTORMETRICS_SOURCE_ENABLED)) {
        Some(new ExecutorMetricsSource)
      } else {
        None
      }

    // create and start the heartbeater for collecting memory metrics
    _heartbeater = new Heartbeater(
      () => SparkContext.this.reportHeartBeat(_executorMetricsSource),
      "driver-heartbeater",
      conf.get(DRIVER_METRICS_POLLING_INTERVAL))
    _heartbeater.start()

    // start TaskScheduler after taskScheduler sets DAGScheduler reference in DAGScheduler's
    // constructor
    _taskScheduler.start()

    _applicationId = _taskScheduler.applicationId()
    _applicationAttemptId = _taskScheduler.applicationAttemptId()
    _conf.set("spark.app.id", _applicationId)
    _applicationAttemptId.foreach { attemptId =>
      _conf.set(APP_ATTEMPT_ID, attemptId)
      _env.blockManager.blockStoreClient.setAppAttemptId(attemptId)
    }

    // initialize after application id and attempt id has been initialized
    _shuffleDriverComponents = ShuffleDataIOUtils.loadShuffleDataIO(_conf).driver()
    _shuffleDriverComponents.initializeApplication().asScala.foreach { case (k, v) =>
      _conf.set(ShuffleDataIOUtils.SHUFFLE_SPARK_CONF_PREFIX + k, v)
    }

    if (_conf.get(UI_REVERSE_PROXY)) {
      val proxyUrl = _conf.get(UI_REVERSE_PROXY_URL).getOrElse("").stripSuffix("/")
      System.setProperty("spark.ui.proxyBase", proxyUrl + "/proxy/" + _applicationId)
    }
    _ui.foreach(_.setAppId(_applicationId))
    _env.blockManager.initialize(_applicationId)
    FallbackStorage.registerBlockManagerIfNeeded(
      _env.blockManager.master, _conf, _hadoopConfiguration)

    // The metrics system for Driver need to be set spark.app.id to app ID.
    // So it should start after we get app ID from the task scheduler and set spark.app.id.
    _env.metricsSystem.start(_conf.get(METRICS_STATIC_SOURCES_ENABLED))

    _eventLogger =
      if (isEventLogEnabled) {
        val logger =
          new EventLoggingListener(_applicationId, _applicationAttemptId, _eventLogDir.get,
            _conf, _hadoopConfiguration)
        logger.start()
        listenerBus.addToEventLogQueue(logger)
        Some(logger)
      } else {
        None
      }

    _cleaner =
      if (_conf.get(CLEANER_REFERENCE_TRACKING)) {
        Some(new ContextCleaner(this, _shuffleDriverComponents))
      } else {
        None
      }
    _cleaner.foreach(_.start())

    val dynamicAllocationEnabled = Utils.isDynamicAllocationEnabled(_conf)
    _executorAllocationManager =
      if (dynamicAllocationEnabled) {
        schedulerBackend match {
          case b: ExecutorAllocationClient =>
            Some(new ExecutorAllocationManager(
              schedulerBackend.asInstanceOf[ExecutorAllocationClient], listenerBus, _conf,
              cleaner = cleaner, resourceProfileManager = resourceProfileManager,
              reliableShuffleStorage = _shuffleDriverComponents.supportsReliableStorage()))
          case _ =>
            None
        }
      } else {
        None
      }
    _executorAllocationManager.foreach(_.start())

    setupAndStartListenerBus()
    postEnvironmentUpdate()
    postApplicationStart()

    // After application started, attach handlers to started server and start handler.
    _ui.foreach(_.attachAllHandlers())
    // Attach the driver metrics servlet handler to the web ui after the metrics system is started.
    _env.metricsSystem.getServletHandlers.foreach(handler => ui.foreach(_.attachHandler(handler)))

    // Make sure the context is stopped if the user forgets about it. This avoids leaving
    // unfinished event logs around after the JVM exits cleanly. It doesn't help if the JVM
    // is killed, though.
    logDebug("Adding shutdown hook") // force eager creation of logger
    _shutdownHookRef = ShutdownHookManager.addShutdownHook(
      ShutdownHookManager.SPARK_CONTEXT_SHUTDOWN_PRIORITY) { () =>
      logInfo("Invoking stop() from shutdown hook")
      try {
        stop()
      } catch {
        case e: Throwable =>
          logWarning("Ignoring Exception while stopping SparkContext from shutdown hook", e)
      }
    }

    // Post init
    _taskScheduler.postStartHook()
    if (isLocal) {
      _env.metricsSystem.registerSource(Executor.executorSourceLocalModeOnly)
    }
    _env.metricsSystem.registerSource(_dagScheduler.metricsSource)
    _env.metricsSystem.registerSource(new BlockManagerSource(_env.blockManager))
    _env.metricsSystem.registerSource(new JVMCPUSource())
    _executorMetricsSource.foreach(_.register(_env.metricsSystem))
    _executorAllocationManager.foreach { e =>
      _env.metricsSystem.registerSource(e.executorAllocationManagerSource)
    }
    appStatusSource.foreach(_env.metricsSystem.registerSource(_))
    _plugins.foreach(_.registerMetrics(applicationId))

    new CallerContext("DRIVER", config.get(APP_CALLER_CONTEXT),
      Some(applicationId), applicationAttemptId).setCurrentContext()
  } catch {
    case NonFatal(e) =>
      logError("Error initializing SparkContext.", e)
      try {
        stop()
      } catch {
        case NonFatal(inner) =>
          logError("Error stopping SparkContext after init error.", inner)
      } finally {
        throw e
      }
  }

  /**
   * Called by the web UI to obtain executor thread dumps.  This method may be expensive.
   * Logs an error and returns None if we failed to obtain a thread dump, which could occur due
   * to an executor being dead or unresponsive or due to network issues while sending the thread
   * dump message back to the driver.
   */
  private[spark] def getExecutorThreadDump(executorId: String): Option[Array[ThreadStackTrace]] = {
    try {
      if (SparkContext.isDriver(executorId)) {
        Some(Utils.getThreadDump())
      } else {
        env.blockManager.master.getExecutorEndpointRef(executorId) match {
          case Some(endpointRef) =>
            Some(endpointRef.askSync[Array[ThreadStackTrace]](TriggerThreadDump))
          case None =>
            logWarning(log"Executor ${MDC(LogKeys.EXECUTOR_ID, executorId)} " +
              log"might already have stopped and can not request thread dump from it.")
            None
        }
      }
    } catch {
      case e: Exception =>
        logError(
          log"Exception getting thread dump from executor ${MDC(LogKeys.EXECUTOR_ID, executorId)}",
          e)
        None
    }
  }

  private[spark] def getTaskThreadDump(
      taskId: Long,
      executorId: String): Option[ThreadStackTrace] = {
    schedulerBackend.getTaskThreadDump(taskId, executorId)
  }

  /**
   * Called by the web UI to obtain executor heap histogram.
   */
  private[spark] def getExecutorHeapHistogram(executorId: String): Option[Array[String]] = {
    try {
      if (SparkContext.isDriver(executorId)) {
        Some(Utils.getHeapHistogram())
      } else {
        env.blockManager.master.getExecutorEndpointRef(executorId) match {
          case Some(endpointRef) =>
            Some(endpointRef.askSync[Array[String]](TriggerHeapHistogram))
          case None =>
            logWarning(log"Executor ${MDC(LogKeys.EXECUTOR_ID, executorId)} " +
              log"might already have stopped and can not request heap histogram from it.")
            None
        }
      }
    } catch {
      case e: Exception =>
        logError(
          log"Exception getting heap histogram from " +
            log"executor ${MDC(LogKeys.EXECUTOR_ID, executorId)}", e)
        None
    }
  }

  private[spark] def getLocalProperties: Properties = localProperties.get()

  private[spark] def setLocalProperties(props: Properties): Unit = {
    localProperties.set(props)
  }

  /**
   * Set a local property that affects jobs submitted from this thread, such as the Spark fair
   * scheduler pool. User-defined properties may also be set here. These properties are propagated
   * through to worker tasks and can be accessed there via
   * [[org.apache.spark.TaskContext#getLocalProperty]].
   *
   * These properties are inherited by child threads spawned from this thread. This
   * may have unexpected consequences when working with thread pools. The standard java
   * implementation of thread pools have worker threads spawn other worker threads.
   * As a result, local properties may propagate unpredictably.
   *
   * To remove/unset property simply set `value` to null e.g. sc.setLocalProperty("key", null)
   */
  def setLocalProperty(key: String, value: String): Unit = {
    if (value == null) {
      localProperties.get.remove(key)
    } else {
      localProperties.get.setProperty(key, value)
    }
  }

  /**
   * Get a local property set in this thread, or null if it is missing. See
   * `org.apache.spark.SparkContext.setLocalProperty`.
   */
  def getLocalProperty(key: String): String =
    Option(localProperties.get).map(_.getProperty(key)).orNull

  /** Set a human readable description of the current job. */
  def setJobDescription(value: String): Unit = {
    setLocalProperty(SparkContext.SPARK_JOB_DESCRIPTION, value)
  }

  /**
   * Assigns a group ID to all the jobs started by this thread until the group ID is set to a
   * different value or cleared.
   *
   * Often, a unit of execution in an application consists of multiple Spark actions or jobs.
   * Application programmers can use this method to group all those jobs together and give a
   * group description. Once set, the Spark web UI will associate such jobs with this group.
   *
   * The application can also use `org.apache.spark.SparkContext.cancelJobGroup` to cancel all
   * running jobs in this group. For example,
   * {{{
   * // In the main thread:
   * sc.setJobGroup("some_job_to_cancel", "some job description")
   * sc.parallelize(1 to 10000, 2).map { i => Thread.sleep(10); i }.count()
   *
   * // In a separate thread:
   * sc.cancelJobGroup("some_job_to_cancel")
   * }}}
   *
   * @param interruptOnCancel If true, then job cancellation will result in `Thread.interrupt()`
   * being called on the job's executor threads. This is useful to help ensure that the tasks
   * are actually stopped in a timely manner, but is off by default due to HDFS-1208, where HDFS
   * may respond to Thread.interrupt() by marking nodes as dead.
   */
  def setJobGroup(groupId: String,
      description: String, interruptOnCancel: Boolean = false): Unit = {
    setLocalProperty(SparkContext.SPARK_JOB_DESCRIPTION, description)
    setLocalProperty(SparkContext.SPARK_JOB_GROUP_ID, groupId)
    // Note: Specifying interruptOnCancel in setJobGroup (rather than cancelJobGroup) avoids
    // changing several public APIs and allows Spark cancellations outside of the cancelJobGroup
    // APIs to also take advantage of this property (e.g., internal job failures or canceling from
    // JobProgressTab UI) on a per-job basis.
    setLocalProperty(SparkContext.SPARK_JOB_INTERRUPT_ON_CANCEL, interruptOnCancel.toString)
  }

  /** Clear the current thread's job group ID and its description. */
  def clearJobGroup(): Unit = {
    setLocalProperty(SparkContext.SPARK_JOB_DESCRIPTION, null)
    setLocalProperty(SparkContext.SPARK_JOB_GROUP_ID, null)
    setLocalProperty(SparkContext.SPARK_JOB_INTERRUPT_ON_CANCEL, null)
  }

  /**
   * Set the behavior of job cancellation from jobs started in this thread.
   *
   * @param interruptOnCancel If true, then job cancellation will result in `Thread.interrupt()`
   * being called on the job's executor threads. This is useful to help ensure that the tasks
   * are actually stopped in a timely manner, but is off by default due to HDFS-1208, where HDFS
   * may respond to Thread.interrupt() by marking nodes as dead.
   *
   * @since 3.5.0
   */
  def setInterruptOnCancel(interruptOnCancel: Boolean): Unit = {
    setLocalProperty(SparkContext.SPARK_JOB_INTERRUPT_ON_CANCEL, interruptOnCancel.toString)
  }

  /**
   * Add a tag to be assigned to all the jobs started by this thread.
   *
   * Often, a unit of execution in an application consists of multiple Spark actions or jobs.
   * Application programmers can use this method to group all those jobs together and give a
   * group tag. The application can use `org.apache.spark.sql.SparkSession.interruptTag` to cancel
   * all running executions with this tag. For example:
   * {{{
   * // In the main thread:
   * sc.addJobTag("myjobs")
   * sc.parallelize(1 to 10000, 2).map { i => Thread.sleep(10); i }.count()
   *
   * // In a separate thread:
   * spark.cancelJobsWithTag("myjobs")
   * }}}
   *
   * There may be multiple tags present at the same time, so different parts of application may use
   * different tags to perform cancellation at different levels of granularity.
   *
   * @param tag The tag to be added. Cannot contain ',' (comma) character.
   *
   * @since 3.5.0
   */
  def addJobTag(tag: String): Unit = addJobTags(Set(tag))

  /**
   * Add multiple tags to be assigned to all the jobs started by this thread.
   * See [[addJobTag]] for more details.
   *
   * @param tags The tags to be added. Cannot contain ',' (comma) character.
   *
   * @since 4.0.0
   */
  def addJobTags(tags: Set[String]): Unit = {
    tags.foreach(SparkContext.throwIfInvalidTag)
    val existingTags = getJobTags()
    val newTags = (existingTags ++ tags).mkString(SparkContext.SPARK_JOB_TAGS_SEP)
    setLocalProperty(SparkContext.SPARK_JOB_TAGS, newTags)
  }

  /**
   * Remove a tag previously added to be assigned to all the jobs started by this thread.
   * Noop if such a tag was not added earlier.
   *
   * @param tag The tag to be removed. Cannot contain ',' (comma) character.
   *
   * @since 3.5.0
   */
  def removeJobTag(tag: String): Unit = removeJobTags(Set(tag))

  /**
   * Remove multiple tags to be assigned to all the jobs started by this thread.
   * See [[removeJobTag]] for more details.
   *
   * @param tags The tags to be removed. Cannot contain ',' (comma) character.
   *
   * @since 4.0.0
   */
  def removeJobTags(tags: Set[String]): Unit = {
    tags.foreach(SparkContext.throwIfInvalidTag)
    val existingTags = getJobTags()
    val newTags = (existingTags -- tags).mkString(SparkContext.SPARK_JOB_TAGS_SEP)
    if (newTags.isEmpty) {
      clearJobTags()
    } else {
      setLocalProperty(SparkContext.SPARK_JOB_TAGS, newTags)
    }
  }

  /**
   * Get the tags that are currently set to be assigned to all the jobs started by this thread.
   *
   * @since 3.5.0
   */
  def getJobTags(): Set[String] = {
    Option(getLocalProperty(SparkContext.SPARK_JOB_TAGS))
      .map(_.split(SparkContext.SPARK_JOB_TAGS_SEP).toSet)
      .getOrElse(Set())
      .filter(!_.isEmpty) // empty string tag should not happen, but be defensive
  }

  /**
   * Clear the current thread's job tags.
   *
   * @since 3.5.0
   */
  def clearJobTags(): Unit = {
    setLocalProperty(SparkContext.SPARK_JOB_TAGS, null)
  }

  /**
   * Execute a block of code in a scope such that all new RDDs created in this body will
   * be part of the same scope. For more detail, see {{org.apache.spark.rdd.RDDOperationScope}}.
   *
   * @note Return statements are NOT allowed in the given body.
   */
  private[spark] def withScope[U](body: => U): U = RDDOperationScope.withScope[U](this)(body)

  // Methods for creating RDDs

  /** Distribute a local Scala collection to form an RDD.
   *
   * @note Parallelize acts lazily. If `seq` is a mutable collection and is altered after the call
   * to parallelize and before the first action on the RDD, the resultant RDD will reflect the
   * modified collection. Pass a copy of the argument to avoid this.
   * @note avoid using `parallelize(Seq())` to create an empty `RDD`. Consider `emptyRDD` for an
   * RDD with no partitions, or `parallelize(Seq[T]())` for an RDD of `T` with empty partitions.
   * @param seq Scala collection to distribute
   * @param numSlices number of partitions to divide the collection into
   * @return RDD representing distributed collection
   */
  def parallelize[T: ClassTag](
      seq: Seq[T],
      numSlices: Int = defaultParallelism): RDD[T] = withScope {
    assertNotStopped()
    new ParallelCollectionRDD[T](this, seq, numSlices, Map[Int, Seq[String]]())
  }

  /**
   * Creates a new RDD[Long] containing elements from `start` to `end`(exclusive), increased by
   * `step` every element.
   *
   * @note if we need to cache this RDD, we should make sure each partition does not exceed limit.
   *
   * @param start the start value.
   * @param end the end value.
   * @param step the incremental step
   * @param numSlices number of partitions to divide the collection into
   * @return RDD representing distributed range
   */
  def range(
      start: Long,
      end: Long,
      step: Long = 1,
      numSlices: Int = defaultParallelism): RDD[Long] = withScope {
    assertNotStopped()
    // when step is 0, range will run infinitely
    require(step != 0, "step cannot be 0")
    val numElements: BigInt = {
      val safeStart = BigInt(start)
      val safeEnd = BigInt(end)
      if ((safeEnd - safeStart) % step == 0 || (safeEnd > safeStart) != (step > 0)) {
        (safeEnd - safeStart) / step
      } else {
        // the remainder has the same sign with range, could add 1 more
        (safeEnd - safeStart) / step + 1
      }
    }
    parallelize(0 until numSlices, numSlices).mapPartitionsWithIndex { (i, _) =>
      val partitionStart = (i * numElements) / numSlices * step + start
      val partitionEnd = (((i + 1) * numElements) / numSlices) * step + start
      def getSafeMargin(bi: BigInt): Long =
        if (bi.isValidLong) {
          bi.toLong
        } else if (bi > 0) {
          Long.MaxValue
        } else {
          Long.MinValue
        }
      val safePartitionStart = getSafeMargin(partitionStart)
      val safePartitionEnd = getSafeMargin(partitionEnd)

      new Iterator[Long] {
        private[this] var number: Long = safePartitionStart
        private[this] var overflow: Boolean = false

        override def hasNext =
          if (!overflow) {
            if (step > 0) {
              number < safePartitionEnd
            } else {
              number > safePartitionEnd
            }
          } else false

        override def next() = {
          val ret = number
          number += step
          if (number < ret ^ step < 0) {
            // we have Long.MaxValue + Long.MaxValue < Long.MaxValue
            // and Long.MinValue + Long.MinValue > Long.MinValue, so iff the step causes a step
            // back, we are pretty sure that we have an overflow.
            overflow = true
          }
          ret
        }
      }
    }
  }

  /** Distribute a local Scala collection to form an RDD.
   *
   * This method is identical to `parallelize`.
   * @param seq Scala collection to distribute
   * @param numSlices number of partitions to divide the collection into
   * @return RDD representing distributed collection
   */
  def makeRDD[T: ClassTag](
      seq: Seq[T],
      numSlices: Int = defaultParallelism): RDD[T] = withScope {
    parallelize(seq, numSlices)
  }

  /**
   * Distribute a local Scala collection to form an RDD, with one or more
   * location preferences (hostnames of Spark nodes) for each object.
   * Create a new partition for each collection item.
   * @param seq list of tuples of data and location preferences (hostnames of Spark nodes)
   * @return RDD representing data partitioned according to location preferences
   */
  def makeRDD[T: ClassTag](seq: Seq[(T, Seq[String])]): RDD[T] = withScope {
    assertNotStopped()
    val indexToPrefs = seq.zipWithIndex.map(t => (t._2, t._1._2)).toMap
    new ParallelCollectionRDD[T](this, seq.map(_._1), math.max(seq.size, 1), indexToPrefs)
  }

  /**
   * Read a text file from HDFS, a local file system (available on all nodes), or any
   * Hadoop-supported file system URI, and return it as an RDD of Strings.
   * The text files must be encoded as UTF-8.
   *
   * @param path path to the text file on a supported file system
   * @param minPartitions suggested minimum number of partitions for the resulting RDD
   * @return RDD of lines of the text file
   */
  def textFile(
      path: String,
      minPartitions: Int = defaultMinPartitions): RDD[String] = withScope {
    assertNotStopped()
    hadoopFile(path, classOf[TextInputFormat], classOf[LongWritable], classOf[Text],
      minPartitions).map(pair => pair._2.toString).setName(path)
  }

  /**
   * Read a directory of text files from HDFS, a local file system (available on all nodes), or any
   * Hadoop-supported file system URI. Each file is read as a single record and returned in a
   * key-value pair, where the key is the path of each file, the value is the content of each file.
   * The text files must be encoded as UTF-8.
   *
   * <p> For example, if you have the following files:
   * {{{
   *   hdfs://a-hdfs-path/part-00000
   *   hdfs://a-hdfs-path/part-00001
   *   ...
   *   hdfs://a-hdfs-path/part-nnnnn
   * }}}
   *
   * Do `val rdd = sparkContext.wholeTextFile("hdfs://a-hdfs-path")`,
   *
   * <p> then `rdd` contains
   * {{{
   *   (a-hdfs-path/part-00000, its content)
   *   (a-hdfs-path/part-00001, its content)
   *   ...
   *   (a-hdfs-path/part-nnnnn, its content)
   * }}}
   *
   * @note Small files are preferred, large file is also allowable, but may cause bad performance.
   * @note On some filesystems, `.../path/&#42;` can be a more efficient way to read all files
   *       in a directory rather than `.../path/` or `.../path`
   * @note Partitioning is determined by data locality. This may result in too few partitions
   *       by default.
   *
   * @param path Directory to the input data files, the path can be comma separated paths as the
   *             list of inputs.
   * @param minPartitions A suggestion value of the minimal splitting number for input data.
   * @return RDD representing tuples of file path and the corresponding file content
   */
  def wholeTextFiles(
      path: String,
      minPartitions: Int = defaultMinPartitions): RDD[(String, String)] = withScope {
    assertNotStopped()
    val job = NewHadoopJob.getInstance(hadoopConfiguration)
    // Use setInputPaths so that wholeTextFiles aligns with hadoopFile/textFile in taking
    // comma separated files as input. (see SPARK-7155)
    NewFileInputFormat.setInputPaths(job, path)
    val updateConf = job.getConfiguration
    new WholeTextFileRDD(
      this,
      classOf[WholeTextFileInputFormat],
      classOf[Text],
      classOf[Text],
      updateConf,
      minPartitions).map(record => (record._1.toString, record._2.toString)).setName(path)
  }

  /**
   * Get an RDD for a Hadoop-readable dataset as PortableDataStream for each file
   * (useful for binary data)
   *
   * For example, if you have the following files:
   * {{{
   *   hdfs://a-hdfs-path/part-00000
   *   hdfs://a-hdfs-path/part-00001
   *   ...
   *   hdfs://a-hdfs-path/part-nnnnn
   * }}}
   *
   * Do
   * `val rdd = sparkContext.binaryFiles("hdfs://a-hdfs-path")`,
   *
   * then `rdd` contains
   * {{{
   *   (a-hdfs-path/part-00000, its content)
   *   (a-hdfs-path/part-00001, its content)
   *   ...
   *   (a-hdfs-path/part-nnnnn, its content)
   * }}}
   *
   * @note Small files are preferred; very large files may cause bad performance.
   * @note On some filesystems, `.../path/&#42;` can be a more efficient way to read all files
   *       in a directory rather than `.../path/` or `.../path`
   * @note Partitioning is determined by data locality. This may result in too few partitions
   *       by default.
   *
   * @param path Directory to the input data files, the path can be comma separated paths as the
   *             list of inputs.
   * @param minPartitions A suggestion value of the minimal splitting number for input data.
   * @return RDD representing tuples of file path and corresponding file content
   */
  def binaryFiles(
      path: String,
      minPartitions: Int = defaultMinPartitions): RDD[(String, PortableDataStream)] = withScope {
    assertNotStopped()
    val job = NewHadoopJob.getInstance(hadoopConfiguration)
    // Use setInputPaths so that binaryFiles aligns with hadoopFile/textFile in taking
    // comma separated files as input. (see SPARK-7155)
    NewFileInputFormat.setInputPaths(job, path)
    val updateConf = job.getConfiguration
    new BinaryFileRDD(
      this,
      classOf[StreamInputFormat],
      classOf[String],
      classOf[PortableDataStream],
      updateConf,
      minPartitions).setName(path)
  }

  /**
   * Load data from a flat binary file, assuming the length of each record is constant.
   *
   * @note We ensure that the byte array for each record in the resulting RDD
   * has the provided record length.
   *
   * @param path Directory to the input data files, the path can be comma separated paths as the
   *             list of inputs.
   * @param recordLength The length at which to split the records
   * @param conf Configuration for setting up the dataset.
   *
   * @return An RDD of data with values, represented as byte arrays
   */
  def binaryRecords(
      path: String,
      recordLength: Int,
      conf: Configuration = hadoopConfiguration): RDD[Array[Byte]] = withScope {
    assertNotStopped()
    conf.setInt(FixedLengthBinaryInputFormat.RECORD_LENGTH_PROPERTY, recordLength)
    val br = newAPIHadoopFile[LongWritable, BytesWritable, FixedLengthBinaryInputFormat](path,
      classOf[FixedLengthBinaryInputFormat],
      classOf[LongWritable],
      classOf[BytesWritable],
      conf = conf)
    br.map { case (k, v) =>
      val bytes = v.copyBytes()
      assert(bytes.length == recordLength, "Byte array does not have correct length")
      bytes
    }
  }

  /**
   * Get an RDD for a Hadoop-readable dataset from a Hadoop JobConf given its InputFormat and other
   * necessary info (e.g. file name for a filesystem-based dataset, table name for HyperTable),
   * using the older MapReduce API (`org.apache.hadoop.mapred`).
   *
   * @param conf JobConf for setting up the dataset. Note: This will be put into a Broadcast.
   *             Therefore if you plan to reuse this conf to create multiple RDDs, you need to make
   *             sure you won't modify the conf. A safe approach is always creating a new conf for
   *             a new RDD.
   * @param inputFormatClass storage format of the data to be read
   * @param keyClass `Class` of the key associated with the `inputFormatClass` parameter
   * @param valueClass `Class` of the value associated with the `inputFormatClass` parameter
   * @param minPartitions Minimum number of Hadoop Splits to generate.
   * @return RDD of tuples of key and corresponding value
   *
   * @note Because Hadoop's RecordReader class re-uses the same Writable object for each
   * record, directly caching the returned RDD or directly passing it to an aggregation or shuffle
   * operation will create many references to the same object.
   * If you plan to directly cache, sort, or aggregate Hadoop writable objects, you should first
   * copy them using a `map` function.
   */
  def hadoopRDD[K, V](
      conf: JobConf,
      inputFormatClass: Class[_ <: InputFormat[K, V]],
      keyClass: Class[K],
      valueClass: Class[V],
      minPartitions: Int = defaultMinPartitions): RDD[(K, V)] = withScope {
    assertNotStopped()

    // This is a hack to enforce loading hdfs-site.xml.
    // See SPARK-11227 for details.
    FileSystem.getLocal(conf)

    // Add necessary security credentials to the JobConf before broadcasting it.
    SparkHadoopUtil.get.addCredentials(conf)
    new HadoopRDD(this, conf, inputFormatClass, keyClass, valueClass, minPartitions)
  }

  /** Get an RDD for a Hadoop file with an arbitrary InputFormat
   *
   * @note Because Hadoop's RecordReader class re-uses the same Writable object for each
   * record, directly caching the returned RDD or directly passing it to an aggregation or shuffle
   * operation will create many references to the same object.
   * If you plan to directly cache, sort, or aggregate Hadoop writable objects, you should first
   * copy them using a `map` function.
   * @param path directory to the input data files, the path can be comma separated paths
   * as a list of inputs
   * @param inputFormatClass storage format of the data to be read
   * @param keyClass `Class` of the key associated with the `inputFormatClass` parameter
   * @param valueClass `Class` of the value associated with the `inputFormatClass` parameter
   * @param minPartitions suggested minimum number of partitions for the resulting RDD
   * @return RDD of tuples of key and corresponding value
   */
  def hadoopFile[K, V](
      path: String,
      inputFormatClass: Class[_ <: InputFormat[K, V]],
      keyClass: Class[K],
      valueClass: Class[V],
      minPartitions: Int = defaultMinPartitions): RDD[(K, V)] = withScope {
    assertNotStopped()

    // This is a hack to enforce loading hdfs-site.xml.
    // See SPARK-11227 for details.
    FileSystem.getLocal(hadoopConfiguration)

    // A Hadoop configuration can be about 10 KiB, which is pretty big, so broadcast it.
    val confBroadcast = broadcast(new SerializableConfiguration(hadoopConfiguration))
    val setInputPathsFunc = (jobConf: JobConf) => FileInputFormat.setInputPaths(jobConf, path)
    new HadoopRDD(
      this,
      confBroadcast,
      Some(setInputPathsFunc),
      inputFormatClass,
      keyClass,
      valueClass,
      minPartitions).setName(path)
  }

  /**
   * Smarter version of hadoopFile() that uses class tags to figure out the classes of keys,
   * values and the InputFormat so that users don't need to pass them directly. Instead, callers
   * can just write, for example,
   * {{{
   * val file = sparkContext.hadoopFile[LongWritable, Text, TextInputFormat](path, minPartitions)
   * }}}
   *
   * @note Because Hadoop's RecordReader class re-uses the same Writable object for each
   * record, directly caching the returned RDD or directly passing it to an aggregation or shuffle
   * operation will create many references to the same object.
   * If you plan to directly cache, sort, or aggregate Hadoop writable objects, you should first
   * copy them using a `map` function.
   * @param path directory to the input data files, the path can be comma separated paths
   * as a list of inputs
   * @param minPartitions suggested minimum number of partitions for the resulting RDD
   * @return RDD of tuples of key and corresponding value
   */
  def hadoopFile[K, V, F <: InputFormat[K, V]]
      (path: String, minPartitions: Int)
      (implicit km: ClassTag[K], vm: ClassTag[V], fm: ClassTag[F]): RDD[(K, V)] = withScope {
    hadoopFile(path,
      fm.runtimeClass.asInstanceOf[Class[F]],
      km.runtimeClass.asInstanceOf[Class[K]],
      vm.runtimeClass.asInstanceOf[Class[V]],
      minPartitions)
  }

  /**
   * Smarter version of hadoopFile() that uses class tags to figure out the classes of keys,
   * values and the InputFormat so that users don't need to pass them directly. Instead, callers
   * can just write, for example,
   * {{{
   * val file = sparkContext.hadoopFile[LongWritable, Text, TextInputFormat](path)
   * }}}
   *
   * @note Because Hadoop's RecordReader class re-uses the same Writable object for each
   * record, directly caching the returned RDD or directly passing it to an aggregation or shuffle
   * operation will create many references to the same object.
   * If you plan to directly cache, sort, or aggregate Hadoop writable objects, you should first
   * copy them using a `map` function.
   * @param path directory to the input data files, the path can be comma separated paths as
   * a list of inputs
   * @return RDD of tuples of key and corresponding value
   */
  def hadoopFile[K, V, F <: InputFormat[K, V]](path: String)
      (implicit km: ClassTag[K], vm: ClassTag[V], fm: ClassTag[F]): RDD[(K, V)] = withScope {
    hadoopFile[K, V, F](path, defaultMinPartitions)
  }

  /**
   * Smarter version of `newApiHadoopFile` that uses class tags to figure out the classes of keys,
   * values and the `org.apache.hadoop.mapreduce.InputFormat` (new MapReduce API) so that user
   * don't need to pass them directly. Instead, callers can just write, for example:
   * ```
   * val file = sparkContext.hadoopFile[LongWritable, Text, TextInputFormat](path)
   * ```
   *
   * @note Because Hadoop's RecordReader class re-uses the same Writable object for each
   * record, directly caching the returned RDD or directly passing it to an aggregation or shuffle
   * operation will create many references to the same object.
   * If you plan to directly cache, sort, or aggregate Hadoop writable objects, you should first
   * copy them using a `map` function.
   * @param path directory to the input data files, the path can be comma separated paths
   * as a list of inputs
   * @return RDD of tuples of key and corresponding value
   */
  def newAPIHadoopFile[K, V, F <: NewInputFormat[K, V]]
      (path: String)
      (implicit km: ClassTag[K], vm: ClassTag[V], fm: ClassTag[F]): RDD[(K, V)] = withScope {
    newAPIHadoopFile(
      path,
      fm.runtimeClass.asInstanceOf[Class[F]],
      km.runtimeClass.asInstanceOf[Class[K]],
      vm.runtimeClass.asInstanceOf[Class[V]])
  }

  /**
   * Get an RDD for a given Hadoop file with an arbitrary new API InputFormat
   * and extra configuration options to pass to the input format.
   *
   * @note Because Hadoop's RecordReader class re-uses the same Writable object for each
   * record, directly caching the returned RDD or directly passing it to an aggregation or shuffle
   * operation will create many references to the same object.
   * If you plan to directly cache, sort, or aggregate Hadoop writable objects, you should first
   * copy them using a `map` function.
   * @param path directory to the input data files, the path can be comma separated paths
   * as a list of inputs
   * @param fClass storage format of the data to be read
   * @param kClass `Class` of the key associated with the `fClass` parameter
   * @param vClass `Class` of the value associated with the `fClass` parameter
   * @param conf Hadoop configuration
   * @return RDD of tuples of key and corresponding value
   */
  def newAPIHadoopFile[K, V, F <: NewInputFormat[K, V]](
      path: String,
      fClass: Class[F],
      kClass: Class[K],
      vClass: Class[V],
      conf: Configuration = hadoopConfiguration): RDD[(K, V)] = withScope {
    assertNotStopped()

    // This is a hack to enforce loading hdfs-site.xml.
    // See SPARK-11227 for details.
    FileSystem.getLocal(hadoopConfiguration)

    // The call to NewHadoopJob automatically adds security credentials to conf,
    // so we don't need to explicitly add them ourselves
    val job = NewHadoopJob.getInstance(conf)
    // Use setInputPaths so that newAPIHadoopFile aligns with hadoopFile/textFile in taking
    // comma separated files as input. (see SPARK-7155)
    NewFileInputFormat.setInputPaths(job, path)
    val updatedConf = job.getConfiguration
    new NewHadoopRDD(this, fClass, kClass, vClass, updatedConf).setName(path)
  }

  /**
   * Get an RDD for a given Hadoop file with an arbitrary new API InputFormat
   * and extra configuration options to pass to the input format.
   *
   * @param conf Configuration for setting up the dataset. Note: This will be put into a Broadcast.
   *             Therefore if you plan to reuse this conf to create multiple RDDs, you need to make
   *             sure you won't modify the conf. A safe approach is always creating a new conf for
   *             a new RDD.
   * @param fClass storage format of the data to be read
   * @param kClass `Class` of the key associated with the `fClass` parameter
   * @param vClass `Class` of the value associated with the `fClass` parameter
   *
   * @note Because Hadoop's RecordReader class re-uses the same Writable object for each
   * record, directly caching the returned RDD or directly passing it to an aggregation or shuffle
   * operation will create many references to the same object.
   * If you plan to directly cache, sort, or aggregate Hadoop writable objects, you should first
   * copy them using a `map` function.
   */
  def newAPIHadoopRDD[K, V, F <: NewInputFormat[K, V]](
      conf: Configuration = hadoopConfiguration,
      fClass: Class[F],
      kClass: Class[K],
      vClass: Class[V]): RDD[(K, V)] = withScope {
    assertNotStopped()

    // This is a hack to enforce loading hdfs-site.xml.
    // See SPARK-11227 for details.
    FileSystem.getLocal(conf)

    // Add necessary security credentials to the JobConf. Required to access secure HDFS.
    val jconf = new JobConf(conf)
    SparkHadoopUtil.get.addCredentials(jconf)
    new NewHadoopRDD(this, fClass, kClass, vClass, jconf)
  }

  /**
   * Get an RDD for a Hadoop SequenceFile with given key and value types.
   *
   * @note Because Hadoop's RecordReader class re-uses the same Writable object for each
   * record, directly caching the returned RDD or directly passing it to an aggregation or shuffle
   * operation will create many references to the same object.
   * If you plan to directly cache, sort, or aggregate Hadoop writable objects, you should first
   * copy them using a `map` function.
   * @param path directory to the input data files, the path can be comma separated paths
   * as a list of inputs
   * @param keyClass `Class` of the key associated with `SequenceFileInputFormat`
   * @param valueClass `Class` of the value associated with `SequenceFileInputFormat`
   * @param minPartitions suggested minimum number of partitions for the resulting RDD
   * @return RDD of tuples of key and corresponding value
   */
  def sequenceFile[K, V](path: String,
      keyClass: Class[K],
      valueClass: Class[V],
      minPartitions: Int
      ): RDD[(K, V)] = withScope {
    assertNotStopped()
    val inputFormatClass = classOf[SequenceFileInputFormat[K, V]]
    hadoopFile(path, inputFormatClass, keyClass, valueClass, minPartitions)
  }

  /**
   * Get an RDD for a Hadoop SequenceFile with given key and value types.
   *
   * @note Because Hadoop's RecordReader class re-uses the same Writable object for each
   * record, directly caching the returned RDD or directly passing it to an aggregation or shuffle
   * operation will create many references to the same object.
   * If you plan to directly cache, sort, or aggregate Hadoop writable objects, you should first
   * copy them using a `map` function.
   * @param path directory to the input data files, the path can be comma separated paths
   * as a list of inputs
   * @param keyClass `Class` of the key associated with `SequenceFileInputFormat`
   * @param valueClass `Class` of the value associated with `SequenceFileInputFormat`
   * @return RDD of tuples of key and corresponding value
   */
  def sequenceFile[K, V](
      path: String,
      keyClass: Class[K],
      valueClass: Class[V]): RDD[(K, V)] = withScope {
    assertNotStopped()
    sequenceFile(path, keyClass, valueClass, defaultMinPartitions)
  }

  /**
   * Version of sequenceFile() for types implicitly convertible to Writables through a
   * WritableConverter. For example, to access a SequenceFile where the keys are Text and the
   * values are IntWritable, you could simply write
   * {{{
   * sparkContext.sequenceFile[String, Int](path, ...)
   * }}}
   *
   * WritableConverters are provided in a somewhat strange way (by an implicit function) to support
   * both subclasses of Writable and types for which we define a converter (e.g. Int to
   * IntWritable). The most natural thing would've been to have implicit objects for the
   * converters, but then we couldn't have an object for every subclass of Writable (you can't
   * have a parameterized singleton object). We use functions instead to create a new converter
   * for the appropriate type. In addition, we pass the converter a ClassTag of its type to
   * allow it to figure out the Writable class to use in the subclass case.
   *
   * @note Because Hadoop's RecordReader class re-uses the same Writable object for each
   * record, directly caching the returned RDD or directly passing it to an aggregation or shuffle
   * operation will create many references to the same object.
   * If you plan to directly cache, sort, or aggregate Hadoop writable objects, you should first
   * copy them using a `map` function.
   * @param path directory to the input data files, the path can be comma separated paths
   * as a list of inputs
   * @param minPartitions suggested minimum number of partitions for the resulting RDD
   * @return RDD of tuples of key and corresponding value
   */
   def sequenceFile[K, V]
       (path: String, minPartitions: Int = defaultMinPartitions)
       (implicit km: ClassTag[K], vm: ClassTag[V],
        kcf: () => WritableConverter[K], vcf: () => WritableConverter[V]): RDD[(K, V)] = {
    withScope {
      assertNotStopped()
      val kc = clean(kcf)()
      val vc = clean(vcf)()
      val format = classOf[SequenceFileInputFormat[Writable, Writable]]
      val writables = hadoopFile(path, format,
        kc.writableClass(km).asInstanceOf[Class[Writable]],
        vc.writableClass(vm).asInstanceOf[Class[Writable]], minPartitions)
      writables.map { case (k, v) => (kc.convert(k), vc.convert(v)) }
    }
  }

  /**
   * Load an RDD saved as a SequenceFile containing serialized objects, with NullWritable keys and
   * BytesWritable values that contain a serialized partition. This is still an experimental
   * storage format and may not be supported exactly as is in future Spark releases. It will also
   * be pretty slow if you use the default serializer (Java serialization),
   * though the nice thing about it is that there's very little effort required to save arbitrary
   * objects.
   *
   * @param path directory to the input data files, the path can be comma separated paths
   * as a list of inputs
   * @param minPartitions suggested minimum number of partitions for the resulting RDD
   * @return RDD representing deserialized data from the file(s)
   */
  def objectFile[T: ClassTag](
      path: String,
      minPartitions: Int = defaultMinPartitions): RDD[T] = withScope {
    assertNotStopped()
    sequenceFile(path, classOf[NullWritable], classOf[BytesWritable], minPartitions)
      .flatMap(x => Utils.deserialize[Array[T]](x._2.getBytes, Utils.getContextOrSparkClassLoader))
  }

  protected[spark] def checkpointFile[T: ClassTag](path: String): RDD[T] = withScope {
    new ReliableCheckpointRDD[T](this, path)
  }

  /** Build the union of a list of RDDs. */
  def union[T: ClassTag](rdds: Seq[RDD[T]]): RDD[T] = withScope {
    val nonEmptyRdds = rdds.filter(!_.partitions.isEmpty)
    val partitioners = nonEmptyRdds.flatMap(_.partitioner).toSet
    if (nonEmptyRdds.forall(_.partitioner.isDefined) && partitioners.size == 1) {
      new PartitionerAwareUnionRDD(this, nonEmptyRdds)
    } else {
      new UnionRDD(this, nonEmptyRdds)
    }
  }

  /** Build the union of a list of RDDs passed as variable-length arguments. */
  def union[T: ClassTag](first: RDD[T], rest: RDD[T]*): RDD[T] = withScope {
    union(Seq(first) ++ rest)
  }

  /** Get an RDD that has no partitions or elements. */
  def emptyRDD[T: ClassTag]: RDD[T] = new EmptyRDD[T](this)

  // Methods for creating shared variables

  /**
   * Register the given accumulator.
   *
   * @note Accumulators must be registered before use, or it will throw exception.
   */
  def register(acc: AccumulatorV2[_, _]): Unit = {
    acc.register(this)
  }

  /**
   * Register the given accumulator with given name.
   *
   * @note Accumulators must be registered before use, or it will throw exception.
   */
  def register(acc: AccumulatorV2[_, _], name: String): Unit = {
    acc.register(this, name = Option(name))
  }

  /**
   * Create and register a long accumulator, which starts with 0 and accumulates inputs by `add`.
   */
  def longAccumulator: LongAccumulator = {
    val acc = new LongAccumulator
    register(acc)
    acc
  }

  /**
   * Create and register a long accumulator, which starts with 0 and accumulates inputs by `add`.
   */
  def longAccumulator(name: String): LongAccumulator = {
    val acc = new LongAccumulator
    register(acc, name)
    acc
  }

  /**
   * Create and register a double accumulator, which starts with 0 and accumulates inputs by `add`.
   */
  def doubleAccumulator: DoubleAccumulator = {
    val acc = new DoubleAccumulator
    register(acc)
    acc
  }

  /**
   * Create and register a double accumulator, which starts with 0 and accumulates inputs by `add`.
   */
  def doubleAccumulator(name: String): DoubleAccumulator = {
    val acc = new DoubleAccumulator
    register(acc, name)
    acc
  }

  /**
   * Create and register a `CollectionAccumulator`, which starts with empty list and accumulates
   * inputs by adding them into the list.
   */
  def collectionAccumulator[T]: CollectionAccumulator[T] = {
    val acc = new CollectionAccumulator[T]
    register(acc)
    acc
  }

  /**
   * Create and register a `CollectionAccumulator`, which starts with empty list and accumulates
   * inputs by adding them into the list.
   */
  def collectionAccumulator[T](name: String): CollectionAccumulator[T] = {
    val acc = new CollectionAccumulator[T]
    register(acc, name)
    acc
  }

  /**
   * Broadcast a read-only variable to the cluster, returning a
   * [[org.apache.spark.broadcast.Broadcast]] object for reading it in distributed functions.
   * The variable will be sent to each executor only once.
   *
   * @param value value to broadcast to the Spark nodes
   * @return `Broadcast` object, a read-only variable cached on each machine
   */
  def broadcast[T: ClassTag](value: T): Broadcast[T] = {
    broadcastInternal(value, serializedOnly = false)
  }

  /**
   * Internal version of broadcast - broadcast a read-only variable to the cluster, returning a
   * [[org.apache.spark.broadcast.Broadcast]] object for reading it in distributed functions.
   * The variable will be sent to each executor only once.
   *
   * @param value value to broadcast to the Spark nodes
   * @param serializedOnly if true, do not cache the unserialized value on the driver
   * @return `Broadcast` object, a read-only variable cached on each machine
   */
  private[spark] def broadcastInternal[T: ClassTag](
      value: T,
      serializedOnly: Boolean): Broadcast[T] = {
    assertNotStopped()
    require(!classOf[RDD[_]].isAssignableFrom(classTag[T].runtimeClass),
      "Can not directly broadcast RDDs; instead, call collect() and broadcast the result.")
    val bc = env.broadcastManager.newBroadcast[T](value, isLocal, serializedOnly)
    val callSite = getCallSite()
    logInfo(log"Created broadcast ${MDC(LogKeys.BROADCAST_ID, bc.id)}" +
      log" from ${MDC(LogKeys.CALL_SITE_SHORT_FORM, callSite.shortForm)}")
    cleaner.foreach(_.registerBroadcastForCleanup(bc))
    bc
  }

  /**
   * Add a file to be downloaded with this Spark job on every node.
   *
   * If a file is added during execution, it will not be available until the next TaskSet starts.
   *
   * @param path can be either a local file, a file in HDFS (or other Hadoop-supported
   * filesystems), or an HTTP, HTTPS or FTP URI. To access the file in Spark jobs,
   * use `SparkFiles.get(fileName)` to find its download location.
   *
   * @note A path can be added only once. Subsequent additions of the same path are ignored.
   */
  def addFile(path: String): Unit = {
    addFile(path, false, false)
  }

  /**
   * Returns a list of file paths that are added to resources.
   */
  def listFiles(): Seq[String] = allAddedFiles.keySet.toSeq

  /**
   * :: Experimental ::
   * Add an archive to be downloaded and unpacked with this Spark job on every node.
   *
   * If an archive is added during execution, it will not be available until the next TaskSet
   * starts.
   *
   * @param path can be either a local file, a file in HDFS (or other Hadoop-supported
   * filesystems), or an HTTP, HTTPS or FTP URI. To access the file in Spark jobs,
   * use `SparkFiles.get(paths-to-files)` to find its download/unpacked location.
   * The given path should be one of .zip, .tar, .tar.gz, .tgz and .jar.
   *
   * @note A path can be added only once. Subsequent additions of the same path are ignored.
   *
   * @since 3.1.0
   */
  @Experimental
  def addArchive(path: String): Unit = {
    addFile(path, false, false, isArchive = true)
  }

  /**
   * :: Experimental ::
   * Returns a list of archive paths that are added to resources.
   *
   * @since 3.1.0
   */
  @Experimental
  def listArchives(): Seq[String] = allAddedArchives.keySet.toSeq

  /**
   * Add a file to be downloaded with this Spark job on every node.
   *
   * If a file is added during execution, it will not be available until the next TaskSet starts.
   *
   * @param path can be either a local file, a file in HDFS (or other Hadoop-supported
   * filesystems), or an HTTP, HTTPS or FTP URI. To access the file in Spark jobs,
   * use `SparkFiles.get(fileName)` to find its download location.
   * @param recursive if true, a directory can be given in `path`. Currently directories are
   * only supported for Hadoop-supported filesystems.
   *
   * @note A path can be added only once. Subsequent additions of the same path are ignored.
   */
  def addFile(path: String, recursive: Boolean): Unit = {
    addFile(path, recursive, false)
  }

  private def addFile(
      path: String, recursive: Boolean, addedOnSubmit: Boolean, isArchive: Boolean = false
    ): Unit = {
    val jobArtifactUUID = JobArtifactSet
      .getCurrentJobArtifactState.map(_.uuid).getOrElse("default")
    val uri = Utils.resolveURI(path)
    val schemeCorrectedURI = uri.getScheme match {
      case null => new File(path).getCanonicalFile.toURI
      case "local" =>
        logWarning(log"File with 'local' scheme ${MDC(LogKeys.PATH, path)} " +
          log"is not supported to add to file server, " +
          log"since it is already available on every node.")
        return
      case _ => uri
    }

    val hadoopPath = new Path(schemeCorrectedURI)
    val scheme = schemeCorrectedURI.getScheme
    if (!Array("http", "https", "ftp", "spark").contains(scheme) && !isArchive) {
      val fs = hadoopPath.getFileSystem(hadoopConfiguration)
      val isDir = fs.getFileStatus(hadoopPath).isDirectory
      if (!isLocal && scheme == "file" && isDir) {
        throw SparkCoreErrors.addLocalDirectoryError(hadoopPath)
      }
      if (!recursive && isDir) {
        throw SparkCoreErrors.addDirectoryError(hadoopPath)
      }
    } else {
      // SPARK-17650: Make sure this is a valid URL before adding it to the list of dependencies
      Utils.validateURL(uri)
    }

    val key = if (!isLocal && scheme == "file") {
      env.rpcEnv.fileServer.addFile(new File(uri.getPath))
    } else if (uri.getScheme == null) {
      schemeCorrectedURI.toString
    } else {
      uri.toString
    }

    val timestamp = if (addedOnSubmit) startTime else System.currentTimeMillis
    // If the session ID was specified from SparkSession, it's from a Spark Connect client.
    // Specify a dedicated directory for Spark Connect client.
    // We're running Spark Connect as a service so regular PySpark path
    // is not affected.
    lazy val root = if (jobArtifactUUID != "default") {
      val newDest = new File(SparkFiles.getRootDirectory(), jobArtifactUUID)
      newDest.mkdir()
      newDest
    } else {
      new File(SparkFiles.getRootDirectory())
    }
    if (
      !isArchive &&
        addedFiles
          .getOrElseUpdate(jobArtifactUUID, new ConcurrentHashMap[String, Long]().asScala)
          .putIfAbsent(key, timestamp).isEmpty) {
      logInfo(log"Added file ${MDC(LogKeys.PATH, path)} at ${MDC(LogKeys.KEY, key)} with" +
        log" timestamp ${MDC(LogKeys.TIMESTAMP, timestamp)}")
      // Fetch the file locally so that closures which are run on the driver can still use the
      // SparkFiles API to access files.
      Utils.fetchFile(uri.toString, root, conf, hadoopConfiguration, timestamp, useCache = false)
      postEnvironmentUpdate()
    } else if (
      isArchive &&
        addedArchives
          .getOrElseUpdate(jobArtifactUUID, new ConcurrentHashMap[String, Long]().asScala)
          .putIfAbsent(
          Utils.getUriBuilder(new URI(key)).fragment(uri.getFragment).build().toString,
          timestamp).isEmpty) {
      logInfo(log"Added archive ${MDC(LogKeys.PATH, path)} at ${MDC(LogKeys.KEY, key)}" +
        log" with timestamp ${MDC(LogKeys.TIMESTAMP, timestamp)}")
      // If the scheme is file, use URI to simply copy instead of downloading.
      val uriToUse = if (!isLocal && scheme == "file") uri else new URI(key)
      val uriToDownload = Utils.getUriBuilder(uriToUse).fragment(null).build()
      val source = Utils.fetchFile(uriToDownload.toString, Utils.createTempDir(), conf,
        hadoopConfiguration, timestamp, useCache = false, shouldUntar = false)
      val dest = new File(
        root,
        if (uri.getFragment != null) uri.getFragment else source.getName)
      logInfo(
        log"Unpacking an archive ${MDC(LogKeys.PATH, path)}" +
          log" (${MDC(LogKeys.BYTE_SIZE, source.length)} bytes)" +
          log" from ${MDC(LogKeys.SOURCE_PATH, source.getAbsolutePath)}" +
          log" to ${MDC(LogKeys.DESTINATION_PATH, dest.getAbsolutePath)}")
      Utils.deleteRecursively(dest)
      Utils.unpack(source, dest)
      postEnvironmentUpdate()
    } else {
      logWarning(log"The path ${MDC(LogKeys.PATH, path)} " +
        log"has been added already. Overwriting of added paths " +
        log"is not supported in the current version.")
    }
  }

  /**
   * :: DeveloperApi ::
   * Register a listener to receive up-calls from events that happen during execution.
   */
  @DeveloperApi
  def addSparkListener(listener: SparkListenerInterface): Unit = {
    listenerBus.addToSharedQueue(listener)
  }

  /**
   * :: DeveloperApi ::
   * Deregister the listener from Spark's listener bus.
   */
  @DeveloperApi
  def removeSparkListener(listener: SparkListenerInterface): Unit = {
    listenerBus.removeListener(listener)
  }

  private[spark] def getExecutorIds(): Seq[String] = {
    schedulerBackend match {
      case b: ExecutorAllocationClient =>
        b.getExecutorIds()
      case _ =>
        logWarning("Requesting executors is not supported by current scheduler.")
        Nil
    }
  }

  /**
   * Get the max number of tasks that can be concurrent launched based on the ResourceProfile
   * could be used, even if some of them are being used at the moment.
   * Note that please don't cache the value returned by this method, because the number can change
   * due to add/remove executors.
   *
   * @param rp ResourceProfile which to use to calculate max concurrent tasks.
   * @return The max number of tasks that can be concurrent launched currently.
   */
  private[spark] def maxNumConcurrentTasks(rp: ResourceProfile): Int = {
    schedulerBackend.maxNumConcurrentTasks(rp)
  }

  /**
   * Update the cluster manager on our scheduling needs. Three bits of information are included
   * to help it make decisions. This applies to the default ResourceProfile.
   * @param numExecutors The total number of executors we'd like to have. The cluster manager
   *                     shouldn't kill any running executor to reach this number, but,
   *                     if all existing executors were to die, this is the number of executors
   *                     we'd want to be allocated.
   * @param localityAwareTasks The number of tasks in all active stages that have a locality
   *                           preferences. This includes running, pending, and completed tasks.
   * @param hostToLocalTaskCount A map of hosts to the number of tasks from all active stages
   *                             that would like to like to run on that host.
   *                             This includes running, pending, and completed tasks.
   * @return whether the request is acknowledged by the cluster manager.
   */
  @DeveloperApi
  def requestTotalExecutors(
      numExecutors: Int,
      localityAwareTasks: Int,
      hostToLocalTaskCount: immutable.Map[String, Int]
    ): Boolean = {
    schedulerBackend match {
      case b: ExecutorAllocationClient =>
        // this is being applied to the default resource profile, would need to add api to support
        // others
        val defaultProfId = resourceProfileManager.defaultResourceProfile.id
        b.requestTotalExecutors(immutable.Map(defaultProfId-> numExecutors),
          immutable.Map(localityAwareTasks -> defaultProfId),
          immutable.Map(defaultProfId -> hostToLocalTaskCount))
      case _ =>
        logWarning("Requesting executors is not supported by current scheduler.")
        false
    }
  }

  /**
   * :: DeveloperApi ::
   * Request an additional number of executors from the cluster manager.
   * @return whether the request is received.
   */
  @DeveloperApi
  def requestExecutors(numAdditionalExecutors: Int): Boolean = {
    schedulerBackend match {
      case b: ExecutorAllocationClient =>
        b.requestExecutors(numAdditionalExecutors)
      case _ =>
        logWarning("Requesting executors is not supported by current scheduler.")
        false
    }
  }

  /**
   * :: DeveloperApi ::
   * Request that the cluster manager kill the specified executors.
   *
   * This is not supported when dynamic allocation is turned on.
   *
   * @note This is an indication to the cluster manager that the application wishes to adjust
   * its resource usage downwards. If the application wishes to replace the executors it kills
   * through this method with new ones, it should follow up explicitly with a call to
   * {{SparkContext#requestExecutors}}.
   *
   * @return whether the request is received.
   */
  @DeveloperApi
  def killExecutors(executorIds: Seq[String]): Boolean = {
    schedulerBackend match {
      case b: ExecutorAllocationClient =>
        require(executorAllocationManager.isEmpty,
          "killExecutors() unsupported with Dynamic Allocation turned on")
        b.killExecutors(executorIds, adjustTargetNumExecutors = true, countFailures = false,
          force = true).nonEmpty
      case _ =>
        logWarning("Killing executors is not supported by current scheduler.")
        false
    }
  }

  /**
   * :: DeveloperApi ::
   * Request that the cluster manager kill the specified executor.
   *
   * @note This is an indication to the cluster manager that the application wishes to adjust
   * its resource usage downwards. If the application wishes to replace the executor it kills
   * through this method with a new one, it should follow up explicitly with a call to
   * {{SparkContext#requestExecutors}}.
   *
   * @return whether the request is received.
   */
  @DeveloperApi
  def killExecutor(executorId: String): Boolean = killExecutors(Seq(executorId))

  /**
   * Request that the cluster manager kill the specified executor without adjusting the
   * application resource requirements.
   *
   * The effect is that a new executor will be launched in place of the one killed by
   * this request. This assumes the cluster manager will automatically and eventually
   * fulfill all missing application resource requests.
   *
   * @note The replace is by no means guaranteed; another application on the same cluster
   * can steal the window of opportunity and acquire this application's resources in the
   * mean time.
   *
   * @return whether the request is received.
   */
  private[spark] def killAndReplaceExecutor(executorId: String): Boolean = {
    schedulerBackend match {
      case b: ExecutorAllocationClient =>
        b.killExecutors(Seq(executorId), adjustTargetNumExecutors = false, countFailures = true,
          force = true).nonEmpty
      case _ =>
        logWarning("Killing executors is not supported by current scheduler.")
        false
    }
  }

  /** The version of Spark on which this application is running. */
  def version: String = SPARK_VERSION

  /**
   * Return a map from the block manager to the max memory available for caching and the remaining
   * memory available for caching.
   */
  def getExecutorMemoryStatus: Map[String, (Long, Long)] = {
    assertNotStopped()
    env.blockManager.master.getMemoryStatus.map { case(blockManagerId, mem) =>
      (blockManagerId.host + ":" + blockManagerId.port, mem)
    }
  }

  /**
   * :: DeveloperApi ::
   * Return information about what RDDs are cached, if they are in mem or on disk, how much space
   * they take, etc.
   */
  @DeveloperApi
  def getRDDStorageInfo: Array[RDDInfo] = {
    getRDDStorageInfo(_ => true)
  }

  private[spark] def getRDDStorageInfo(filter: RDD[_] => Boolean): Array[RDDInfo] = {
    assertNotStopped()
    val rddInfos = persistentRdds.values.filter(filter).map(RDDInfo.fromRdd).toArray
    rddInfos.foreach { rddInfo =>
      val rddId = rddInfo.id
      val rddStorageInfo = statusStore.asOption(statusStore.rdd(rddId))
      rddInfo.numCachedPartitions = rddStorageInfo.map(_.numCachedPartitions).getOrElse(0)
      rddInfo.memSize = rddStorageInfo.map(_.memoryUsed).getOrElse(0L)
      rddInfo.diskSize = rddStorageInfo.map(_.diskUsed).getOrElse(0L)
    }
    rddInfos.filter(_.isCached)
  }

  /**
   * Returns an immutable map of RDDs that have marked themselves as persistent via cache() call.
   *
   * @note This does not necessarily mean the caching or computation was successful.
   */
  def getPersistentRDDs: Map[Int, RDD[_]] = persistentRdds.toMap

  /**
   * :: DeveloperApi ::
   * Return pools for fair scheduler
   */
  @DeveloperApi
  def getAllPools: Seq[Schedulable] = {
    assertNotStopped()
    // TODO(xiajunluan): We should take nested pools into account
    taskScheduler.rootPool.schedulableQueue.asScala.toSeq
  }

  /**
   * :: DeveloperApi ::
   * Return the pool associated with the given name, if one exists
   */
  @DeveloperApi
  def getPoolForName(pool: String): Option[Schedulable] = {
    assertNotStopped()
    Option(taskScheduler.rootPool.schedulableNameToSchedulable.get(pool))
  }

  /**
   * Return current scheduling mode
   */
  def getSchedulingMode: SchedulingMode.SchedulingMode = {
    assertNotStopped()
    taskScheduler.schedulingMode
  }

  /**
   * Gets the locality information associated with the partition in a particular rdd
   * @param rdd of interest
   * @param partition to be looked up for locality
   * @return list of preferred locations for the partition
   */
  private [spark] def getPreferredLocs(rdd: RDD[_], partition: Int): Seq[TaskLocation] = {
    dagScheduler.getPreferredLocs(rdd, partition)
  }

  /**
   * Register an RDD to be persisted in memory and/or disk storage
   */
  private[spark] def persistRDD(rdd: RDD[_]): Unit = {
    persistentRdds(rdd.id) = rdd
  }

  /**
   * Unpersist an RDD from memory and/or disk storage
   */
  private[spark] def unpersistRDD(rddId: Int, blocking: Boolean): Unit = {
    env.blockManager.master.removeRdd(rddId, blocking)
    persistentRdds.remove(rddId)
    listenerBus.post(SparkListenerUnpersistRDD(rddId))
  }

  /**
   * Adds a JAR dependency for all tasks to be executed on this `SparkContext` in the future.
   *
   * If a jar is added during execution, it will not be available until the next TaskSet starts.
   *
   * @param path can be either a local file, a file in HDFS (or other Hadoop-supported filesystems),
   * an HTTP, HTTPS or FTP URI, or local:/path for a file on every worker node.
   *
   * @note A path can be added only once. Subsequent additions of the same path are ignored.
   */
  def addJar(path: String): Unit = {
    addJar(path, false)
  }

  private def addJar(path: String, addedOnSubmit: Boolean): Unit = {
    val jobArtifactUUID = JobArtifactSet
      .getCurrentJobArtifactState.map(_.uuid).getOrElse("default")
    def addLocalJarFile(file: File): Seq[String] = {
      try {
        if (!file.exists()) {
          throw new FileNotFoundException(s"Jar ${file.getAbsolutePath} not found")
        }
        if (file.isDirectory) {
          throw new IllegalArgumentException(
            s"Directory ${file.getAbsoluteFile} is not allowed for addJar")
        }

        Seq(env.rpcEnv.fileServer.addJar(file))
      } catch {
        case NonFatal(e) =>
          logError(log"Failed to add ${MDC(LogKeys.PATH, path)} to Spark environment", e)
          Nil
      }
    }

    def checkRemoteJarFile(path: String): Seq[String] = {
      val hadoopPath = new Path(path)
      val scheme = hadoopPath.toUri.getScheme
      if (!Array("http", "https", "ftp", "spark").contains(scheme)) {
        try {
          val fs = hadoopPath.getFileSystem(hadoopConfiguration)
          if (!fs.exists(hadoopPath)) {
            throw new FileNotFoundException(s"Jar ${path} not found")
          }
          if (fs.getFileStatus(hadoopPath).isDirectory) {
            throw new IllegalArgumentException(
              s"Directory ${path} is not allowed for addJar")
          }
          Seq(path)
        } catch {
          case NonFatal(e) =>
            logError(log"Failed to add ${MDC(LogKeys.PATH, path)} to Spark environment", e)
            Nil
        }
      } else {
        Seq(path)
      }
    }

    if (path == null || path.isEmpty) {
      logWarning("null or empty path specified as parameter to addJar")
    } else {
      val (keys, scheme) = if (path.contains("\\") && Utils.isWindows) {
        // For local paths with backslashes on Windows, URI throws an exception
        (addLocalJarFile(new File(path)), "local")
      } else {
        val uri = Utils.resolveURI(path)
        // SPARK-17650: Make sure this is a valid URL before adding it to the list of dependencies
        Utils.validateURL(uri)
        val uriScheme = uri.getScheme
        val jarPaths = uriScheme match {
          // A JAR file which exists only on the driver node
          case null =>
            // SPARK-22585 path without schema is not url encoded
            addLocalJarFile(new File(uri.getPath))
          // A JAR file which exists only on the driver node
          case "file" => addLocalJarFile(new File(uri.getPath))
          // A JAR file which exists locally on every worker node
          case "local" => Seq("file:" + uri.getPath)
          case "ivy" =>
            // Since `new Path(path).toUri` will lose query information,
            // so here we use `URI.create(path)`
            DependencyUtils.resolveMavenDependencies(URI.create(path))
              .flatMap(jar => addLocalJarFile(new File(jar)))
          case _ => checkRemoteJarFile(path)
        }
        (jarPaths, uriScheme)
      }
      if (keys.nonEmpty) {
        val timestamp = if (addedOnSubmit) startTime else System.currentTimeMillis
        val (added, existed) = keys.partition(addedJars
          .getOrElseUpdate(jobArtifactUUID, new ConcurrentHashMap[String, Long]().asScala)
          .putIfAbsent(_, timestamp).isEmpty)
        if (added.nonEmpty) {
          val jarMessage = if (scheme != "ivy") {
            log"Added JAR"
          } else {
            log"Added dependency jars of Ivy URI"
          }
          logInfo(jarMessage + log" ${MDC(LogKeys.PATH, path)}" +
            log" at ${MDC(LogKeys.ADDED_JARS, added.mkString(","))}" +
            log" with timestamp ${MDC(LogKeys.TIMESTAMP, timestamp)}")
          postEnvironmentUpdate()
        }
        if (existed.nonEmpty) {
          val jarMessage = if (scheme != "ivy") "JAR" else "dependency jars of Ivy URI"
          logWarning(log"The ${MDC(LogKeys.JAR_MESSAGE, jarMessage)} ${MDC(LogKeys.PATH, path)} " +
            log"at ${MDC(LogKeys.EXISTING_PATH, existed.mkString(","))} has been added already." +
            log" Overwriting of added jar is not supported in the current version.")
        }
      }
    }
  }

  /**
   * Returns a list of jar files that are added to resources.
   */
  def listJars(): Seq[String] = allAddedJars.keySet.toSeq

  /**
   * When stopping SparkContext inside Spark components, it's easy to cause dead-lock since Spark
   * may wait for some internal threads to finish. It's better to use this method to stop
   * SparkContext instead.
   */
  private[spark] def stopInNewThread(): Unit = {
    new Thread("stop-spark-context") {
      setDaemon(true)

      override def run(): Unit = {
        try {
          SparkContext.this.stop()
        } catch {
          case e: Throwable =>
            logError(e.getMessage, e)
            throw e
        }
      }
    }.start()
  }

  /**
   * Shut down the SparkContext.
   */
  def stop(): Unit = stop(0)

  /**
   * Shut down the SparkContext with exit code that will passed to scheduler backend.
   * In client mode, client side may call `SparkContext.stop()` to clean up but exit with
   * code not equal to 0. This behavior cause resource scheduler such as `ApplicationMaster`
   * exit with success status but client side exited with failed status. Spark can call
   * this method to stop SparkContext and pass client side correct exit code to scheduler backend.
   * Then scheduler backend should send the exit code to corresponding resource scheduler
   * to keep consistent.
   *
   * @param exitCode Specified exit code that will passed to scheduler backend in client mode.
   */
  def stop(exitCode: Int): Unit = {
    stopSite = Some(getCallSite())
    logInfo(log"SparkContext is stopping with exitCode ${MDC(LogKeys.EXIT_CODE, exitCode)}" +
      log" from ${MDC(LogKeys.STOP_SITE_SHORT_FORM, stopSite.get.shortForm)}.")
    if (LiveListenerBus.withinListenerThread.value) {
      throw new SparkException(s"Cannot stop SparkContext within listener bus thread.")
    }
    // Use the stopping variable to ensure no contention for the stop scenario.
    // Still track the stopped variable for use elsewhere in the code.
    if (!stopped.compareAndSet(false, true)) {
      logInfo("SparkContext already stopped.")
      return
    }
    if (_shutdownHookRef != null) {
      ShutdownHookManager.removeShutdownHook(_shutdownHookRef)
    }

    if (listenerBus != null) {
      Utils.tryLogNonFatalError {
        postApplicationEnd(exitCode)
      }
    }
    Utils.tryLogNonFatalError {
      _driverLogger.foreach(_.stop())
    }
    Utils.tryLogNonFatalError {
      _ui.foreach(_.stop())
    }
    Utils.tryLogNonFatalError {
      _cleaner.foreach(_.stop())
    }
    Utils.tryLogNonFatalError {
      _executorAllocationManager.foreach(_.stop())
    }
    if (_dagScheduler != null) {
      Utils.tryLogNonFatalError {
        _dagScheduler.stop(exitCode)
      }
      _dagScheduler = null
    }
    // In case there are still events being posted during the shutdown of plugins,
    // invoke the shutdown of each plugin before the listenerBus is stopped.
    Utils.tryLogNonFatalError {
      _plugins.foreach(_.shutdown())
    }
    if (_listenerBusStarted) {
      Utils.tryLogNonFatalError {
        listenerBus.stop()
        _listenerBusStarted = false
      }
    }
    if (env != null) {
      Utils.tryLogNonFatalError {
        env.metricsSystem.report()
      }
    }
    Utils.tryLogNonFatalError {
      FallbackStorage.cleanUp(_conf, _hadoopConfiguration)
    }
    Utils.tryLogNonFatalError {
      _eventLogger.foreach(_.stop())
    }
    if (_shuffleDriverComponents != null) {
      Utils.tryLogNonFatalError {
        _shuffleDriverComponents.cleanupApplication()
      }
    }
    if (_heartbeater != null) {
      Utils.tryLogNonFatalError {
        _heartbeater.stop()
      }
      _heartbeater = null
    }
    if (env != null && _heartbeatReceiver != null) {
      Utils.tryLogNonFatalError {
        env.rpcEnv.stop(_heartbeatReceiver)
      }
    }
    Utils.tryLogNonFatalError {
      _progressBar.foreach(_.stop())
    }
    _taskScheduler = null
    // TODO: Cache.stop()?
    if (_env != null) {
      Utils.tryLogNonFatalError {
        _env.stop()
      }
      SparkEnv.set(null)
    }
    if (_statusStore != null) {
      _statusStore.close()
    }
    // Clear this `InheritableThreadLocal`, or it will still be inherited in child threads even this
    // `SparkContext` is stopped.
    localProperties.remove()
    ResourceProfile.clearDefaultProfile()
    // Unset YARN mode system env variable, to allow switching between cluster types.
    SparkContext.clearActiveContext()
    logInfo(log"Successfully stopped SparkContext (Uptime: " +
      log"${MDC(LogKeys.TOTAL_TIME, System.currentTimeMillis() - startTime)} ms)")
  }


  /**
   * Get Spark's home location from either a value set through the constructor,
   * or the spark.home Java property, or the SPARK_HOME environment variable
   * (in that order of preference). If neither of these is set, return None.
   */
  private[spark] def getSparkHome(): Option[String] = {
    conf.getO

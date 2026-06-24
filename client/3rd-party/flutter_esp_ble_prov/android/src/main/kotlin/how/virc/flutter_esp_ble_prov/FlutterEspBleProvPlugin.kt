package how.virc.flutter_esp_ble_prov

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import com.espressif.provisioning.*
import com.espressif.provisioning.listeners.BleScanListener
import com.espressif.provisioning.listeners.ProvisionListener
import com.espressif.provisioning.listeners.ResponseListener
import com.espressif.provisioning.listeners.WiFiScanListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import org.greenrobot.eventbus.EventBus
import org.greenrobot.eventbus.Subscribe
import org.greenrobot.eventbus.ThreadMode


/**
 * The data required to be able to connect to an Espressif BLE device.
 *
 * @param device The BLE device from a BLE scan
 * @param scanResult The ScanResult from a BLE scan
 */
class BleConnector(val device: BluetoothDevice, scanResult: ScanResult) {

  /**
   * The service ID used when connecting
   */
  val primaryServiceUuid: String

  init {
    primaryServiceUuid = scanResult.scanRecord?.serviceUuids?.get(0)?.toString() ?: ""
  }
}


/**
 * Combined context from a method channel call from the Flutter side.
 */
class ResultGuard(private val result: Result) {
  private var completed = false

  fun success(value: Any?) {
    if (completed) return
    completed = true
    result.success(value)
  }

  fun error(code: String, message: String?, details: Any?) {
    if (completed) return
    completed = true
    result.error(code, message, details)
  }
}
class CallContext(val call: MethodCall, val result: Result) {

  /**
   * Extracts an argument's value from the method call, and returns an error condition if it is not
   * present.
   */
  fun arg(name: String): String? {
    val v = call.argument<String>(name)
    if (v == null) {
      result.error("E0", "Missing argument: $name", "The argument $name was not provided")
    }
    return v
  }

  /**
   * Extracts a byte array argument's value from the method call.
   */
  fun argBytes(name: String): ByteArray? {
    val v = call.argument<ByteArray>(name)
    if (v == null) {
      result.error("E0", "Missing argument: $name", "The argument $name was not provided")
    }
    return v
  }

}


/**
 * Allows for asynchronously requesting permissions based on platform version.
 *
 * The version switch is required because Bluetooth permission requirements changed at S (31).
 *
 * Concurrent calls to [ensure] are queued: only one system permission dialog is shown at a time.
 * All callers that arrive while a dialog is already visible will be notified together once that
 * single dialog is dismissed, receiving the same grant result.
 */
class PermissionManager(val boss: Boss) : PluginRegistry.RequestPermissionsResultListener {

  // Callers waiting for the in-flight permission dialog to complete.
  private val pendingCallbacks = mutableListOf<(Boolean) -> Unit>()

  // Whether a system permission dialog is currently being shown.
  private var isRequesting = false

  /**
   * Required permissions for the current version of the SDK.
   */
  val permissions: Array<String>
    get() {
      // https://developer.android.com/guide/topics/connectivity/bluetooth/permissions
      return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
      } else {
        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.BLUETOOTH, Manifest.permission.BLUETOOTH_ADMIN)
      }
    }

  /**
   * Check permissions are granted and request them otherwise. Invokes the
   * callback with `true` if *all* requested permissions are granted, `false`
   * otherwise.
   *
   * If a permission dialog is already showing, the callback is queued and will
   * be notified together with the original caller when that dialog is dismissed.
   */
  fun ensure(fCallback: (Boolean) -> Unit) {
    val toRequest = permissions.filter {
      ActivityCompat.checkSelfPermission(boss.platformActivity, it) != PackageManager.PERMISSION_GRANTED
    }

    if (toRequest.isEmpty()) {
      fCallback(true)
      return
    }

    // Enqueue the callback regardless; only open a new dialog if one isn't already showing.
    pendingCallbacks.add(fCallback)
    if (!isRequesting) {
      isRequesting = true
      ActivityCompat.requestPermissions(boss.platformActivity, toRequest.toTypedArray(), 0)
    }
  }

  /**
   * Called on permission request result. Notifies all queued callers with the
   * same result and clears the queue.
   */
  override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
    boss.d("permission result")
    isRequesting = false
    val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
    val toNotify = pendingCallbacks.toList()
    pendingCallbacks.clear()
    toNotify.forEach { it(granted) }
    return true
  }
}


abstract class ActionManager(val boss: Boss) {
  abstract fun call(ctx: CallContext)
}


/**
 * Overall controller for method handling and state.
 *
 * Everything is asynchronous here, and this class handles that stuff through a series of
 * "manager" classes.
 */
class Boss {

  private val logTag = "FlutterEspBleProv"

  // Method names as called from Flutter across the channel.
  private val scanBleMethod = "scanBleDevices"
  private val scanWifiMethod = "scanWifiNetworks"
  private val scanWifiWithDetailsMethod = "scanWifiNetworksWithDetails"
  private val provisionWifiMethod = "provisionWifi"
  private val sendDataMethod = "sendDataToCustomEndPoint"
  private val platformVersionMethod = "getPlatformVersion"

  /**
   * The available scanned BLE devices.
   */
  val devices = mutableMapOf<String, BleConnector>()

  /**
   * The available WiFi networks for the most recently scanned BLE device.
   */
  val networks = mutableSetOf<String>()

  // Managers performing the various actions
  private val permissionManager: PermissionManager = PermissionManager(this)
  private val bleScanner: BleScanManager = BleScanManager(this)
  private val wifiScanner: WifiScanManager = WifiScanManager(this)
  private val wifiScannerWithDetails: WifiScanWithDetailsManager = WifiScanWithDetailsManager(this)
  private val wifiProvisioner: WifiProvisionManager = WifiProvisionManager(this)
  private val sendDataManager: SendDataManager = SendDataManager(this)

  private lateinit var platformContext: Context
  lateinit var platformActivity: Activity

  val espManager: ESPProvisionManager get() = ESPProvisionManager.getInstance(platformContext)

  // Logging shortcuts
  fun d(msg: String) = Log.d(logTag, msg)
  fun e(msg: String) = Log.e(logTag, msg)
  fun i(msg: String) = Log.i(logTag, msg)

  fun connector(deviceName: String): BleConnector? {
    return devices[deviceName]
  }

  private fun parseSecurity(security: String?): ESPConstants.SecurityType {
    return when (security?.lowercase()) {
      "secure1" -> ESPConstants.SecurityType.SECURITY_1
      "secure2" -> ESPConstants.SecurityType.SECURITY_2
      else -> ESPConstants.SecurityType.SECURITY_0
    }
  }

  /**
   * Connect to a named device with proofOfPossession string, and once connected, execute the
   * callback.
   */
  fun connect(
    conn: BleConnector,
    proofOfPossession: String,
    security: String?,
    onFailureCallback: (String, String, String?) -> Unit,
    onConnectCallback: (ESPDevice) -> Unit
  ) {
    val securityType = parseSecurity(security)
    val esp = espManager.createESPDevice(ESPConstants.TransportType.TRANSPORT_BLE, securityType)
    val handler = Handler(Looper.getMainLooper())
    var completed = false
    lateinit var subscriber: Any
    lateinit var timeoutRunnable: Runnable

    fun finishFailure(code: String, message: String, details: String? = null) {
      if (completed) return
      completed = true
      handler.removeCallbacks(timeoutRunnable)
      try {
        EventBus.getDefault().unregister(subscriber)
      } catch (_: java.lang.Exception) {
      }
      try {
        esp.disconnectDevice()
      } catch (_: java.lang.Exception) {
      }
      onFailureCallback(code, message, details)
    }

    timeoutRunnable = Runnable {
      finishFailure("E_CONNECT_TIMEOUT", "BLE connection timed out", "Device: ${conn.device.name}")
    }

    subscriber = object {
      @Subscribe(threadMode = ThreadMode.MAIN)
      fun onEvent(event: DeviceConnectionEvent) {
        d("bus event $event ${event.eventType}")
        when (event.eventType) {
          ESPConstants.EVENT_DEVICE_CONNECTED -> {
            if (completed) return
            completed = true
            handler.removeCallbacks(timeoutRunnable)
            EventBus.getDefault().unregister(this)
            esp.proofOfPossession = proofOfPossession
            onConnectCallback(esp)
          }
          ESPConstants.EVENT_DEVICE_CONNECTION_FAILED -> {
            finishFailure("E_CONNECT_FAILED", "BLE connection failed", "Device: ${conn.device.name}")
          }
          ESPConstants.EVENT_DEVICE_DISCONNECTED -> {
            d("Ignoring disconnected event while waiting for BLE connection")
          }
        }
      }
    }

    EventBus.getDefault().register(subscriber)
    handler.postDelayed(timeoutRunnable, 30000)
    esp.connectBLEDevice(conn.device, conn.primaryServiceUuid)
  }

  fun call(call: MethodCall, result: Result) {
    permissionManager.ensure(fun(granted: Boolean) {
      if (!granted) {
        // propagate a permission error back to Dart and abort further work
        result.error("PERMISSION_DENIED", "Required permissions not granted", null)
        return@ensure
      }

      val ctx = CallContext(call, result)
      when (call.method) {
        platformVersionMethod -> getPlatformVersion(ctx)
        scanBleMethod -> bleScanner.call(ctx)
        scanWifiMethod -> wifiScanner.call(ctx)
        scanWifiWithDetailsMethod -> wifiScannerWithDetails.call(ctx)
        provisionWifiMethod -> wifiProvisioner.call(ctx)
        sendDataMethod -> sendDataManager.call(ctx)
        else -> result.notImplemented()
      }
    })
  }

  private fun getPlatformVersion(ctx: CallContext) {
    ctx.result.success("Android ${Build.VERSION.RELEASE}")
  }

  fun attachActivity(activity: Activity) {
    platformActivity = activity
  }

  fun attachContext(context: Context) {
    platformContext = context
  }

  fun attachBinding(binding: ActivityPluginBinding) {
    binding.addRequestPermissionsResultListener(permissionManager)
  }

  fun detachBinding(binding: ActivityPluginBinding) {
    binding.removeRequestPermissionsResultListener(permissionManager)
  }
}


class BleScanManager(boss: Boss) : ActionManager(boss) {

  @SuppressLint("MissingPermission")
  override fun call(ctx: CallContext) {
    boss.d("searchBleEspDevices: start")
    val prefix = ctx.arg("prefix") ?: return
    boss.devices.clear()

    boss.espManager.searchBleEspDevices(prefix, object : BleScanListener {
      override fun scanStartFailed() {
        boss.d("searchBleEspDevices: scanStartFailed")
        ctx.result.error("E_SCAN_FAILED", "BLE scan failed to start", "Please check if Bluetooth is enabled")
      }

      override fun onPeripheralFound(device: BluetoothDevice?, scanResult: ScanResult?) {
        device ?: return
        scanResult ?: return
        boss.devices.put(device.name, BleConnector(device, scanResult))
      }

      override fun scanCompleted() {
        ctx.result.success(ArrayList<String>(boss.devices.keys))
        boss.d("searchBleEspDevices: scanComplete")
      }

      override fun onFailure(e: java.lang.Exception?) {
        boss.e("searchBleEspDevices: onFailure $e")
        ctx.result.error("E_SCAN_ERROR", "BLE scan error", "Exception details: $e")
      }

    })
  }

}

class WifiScanManager(boss: Boss) : ActionManager(boss) {
  override fun call(ctx: CallContext) {
    val guardedResult = ResultGuard(ctx.result)
    val name = ctx.arg("deviceName") ?: return
    val proofOfPossession = ctx.arg("proofOfPossession") ?: return
    val security = ctx.call.argument<String>("security")
    val conn = boss.connector(name)
    if (conn == null) {
      guardedResult.error("E_DEVICE_NOT_FOUND", "BLE device is not available", "Device: $name")
      return
    }
    boss.networks.clear()
    boss.d("esp connect: start")
    boss.connect(conn, proofOfPossession, security, guardedResult::error) { esp ->
      boss.d("scanNetworks: start")
      val handler = Handler(Looper.getMainLooper())
      var completed = false
      lateinit var timeoutRunnable: Runnable

      fun finish(action: () -> Unit) {
        if (completed) return
        completed = true
        handler.removeCallbacks(timeoutRunnable)
        try {
          esp.disconnectDevice()
        } catch (_: java.lang.Exception) {
        }
        handler.postDelayed({ action() }, 600)
      }

      timeoutRunnable = Runnable {
        boss.e("scanNetworks: timeout")
        finish { guardedResult.error("E_WIFI_SCAN_TIMEOUT", "WiFi scan timed out", "Device: $name") }
      }

      handler.postDelayed(timeoutRunnable, 15000)
      esp.scanNetworks(object : WiFiScanListener {
        override fun onWifiListReceived(wifiList: ArrayList<WiFiAccessPoint>?) {
          if (wifiList == null) {
            finish { guardedResult.error("E1", "WiFi scan failed", "WiFi list is null") }
            return
          }
          wifiList.forEach { boss.networks.add(it.wifiName) }
          boss.d("scanNetworks: complete ${boss.networks}")
          Handler(Looper.getMainLooper()).post {
            finish { guardedResult.success(ArrayList<String>(boss.networks)) }
          }
          boss.d("scanNetworks: complete 2 ${boss.networks}")
        }

        override fun onWiFiScanFailed(e: java.lang.Exception?) {
          boss.e("scanNetworks: error $e")
          finish { guardedResult.error("E1", "WiFi scan failed", "Exception details $e") }
        }
      })
    }
  }
}
class WifiScanWithDetailsManager(boss: Boss) : ActionManager(boss) {
  override fun call(ctx: CallContext) {
    val guardedResult = ResultGuard(ctx.result)
    val name = ctx.arg("deviceName") ?: return
    val proofOfPossession = ctx.arg("proofOfPossession") ?: return
    val security = ctx.call.argument<String>("security")
    val conn = boss.connector(name)
    if (conn == null) {
      guardedResult.error("E_DEVICE_NOT_FOUND", "BLE device is not available", "Device: $name")
      return
    }
    boss.d("esp connect: start")
    boss.connect(conn, proofOfPossession, security, guardedResult::error) { esp ->
      boss.d("scanNetworksWithDetails: start")
      val handler = Handler(Looper.getMainLooper())
      var completed = false
      lateinit var timeoutRunnable: Runnable

      fun finish(action: () -> Unit) {
        if (completed) return
        completed = true
        handler.removeCallbacks(timeoutRunnable)
        try {
          esp.disconnectDevice()
        } catch (_: java.lang.Exception) {
        }
        handler.postDelayed({ action() }, 600)
      }

      timeoutRunnable = Runnable {
        boss.e("scanNetworksWithDetails: timeout")
        finish { guardedResult.error("E_WIFI_SCAN_TIMEOUT", "WiFi scan timed out", "Device: $name") }
      }

      handler.postDelayed(timeoutRunnable, 15000)
      esp.scanNetworks(object : WiFiScanListener {
        override fun onWifiListReceived(wifiList: ArrayList<WiFiAccessPoint>?) {
          if (wifiList == null) {
            finish { guardedResult.error("E1", "WiFi scan failed", "WiFi list is null") }
            return
          }
          val networks = wifiList.map { accessPoint ->
            mapOf(
              "ssid" to accessPoint.wifiName,
              "rssi" to accessPoint.rssi,
              "security" to accessPoint.security
            )
          }
          boss.d("scanNetworksWithDetails: complete ${networks}")
          Handler(Looper.getMainLooper()).post {
            finish { guardedResult.success(networks) }
          }
          boss.d("scanNetworksWithDetails: complete 2 ${networks}")
        }

        override fun onWiFiScanFailed(e: java.lang.Exception?) {
          boss.e("scanNetworksWithDetails: error $e")
          finish { guardedResult.error("E1", "WiFi scan failed", "Exception details $e") }
        }
      })
    }
  }
}
class WifiProvisionManager(boss: Boss) : ActionManager(boss) {
  override fun call(ctx: CallContext) {
    val guardedResult = ResultGuard(ctx.result)
    boss.e("provisionWifi ${ctx.call.arguments}")
    val ssid = ctx.arg("ssid") ?: return
    val passphrase = ctx.arg("passphrase") ?: return
    val deviceName = ctx.arg("deviceName") ?: return
    val proofOfPossession = ctx.arg("proofOfPossession") ?: return
    val security = ctx.call.argument<String>("security")
    val conn = boss.connector(deviceName)
    if (conn == null) {
      guardedResult.error("E_DEVICE_NOT_FOUND", "BLE device is not available", "Device: $deviceName")
      return
    }

    boss.connect(conn, proofOfPossession, security, guardedResult::error) { esp ->
      boss.d("provision: start")
      val handler = Handler(Looper.getMainLooper())
      var completed = false
      lateinit var timeoutRunnable: Runnable

      fun finish(value: Boolean) {
        if (completed) return
        completed = true
        handler.removeCallbacks(timeoutRunnable)
        try {
          esp.disconnectDevice()
        } catch (_: java.lang.Exception) {
        }
        handler.postDelayed({ guardedResult.success(value) }, 600)
      }

      timeoutRunnable = Runnable {
        boss.e("provision: timeout")
        finish(false)
      }

      handler.postDelayed(timeoutRunnable, 45000)
      esp.provision(ssid, passphrase, object : ProvisionListener {
        override fun createSessionFailed(e: java.lang.Exception?) {
          boss.e("wifiprovision createSessionFailed $e")
          finish(false)
        }

        override fun wifiConfigSent() {
          boss.d("wifiConfigSent")
        }

        override fun wifiConfigFailed(e: java.lang.Exception?) {
          boss.e("wifiConfiFailed $e")
          finish(false)
        }

        override fun wifiConfigApplied() {
          boss.d("wifiConfigApplied")
        }

        override fun wifiConfigApplyFailed(e: java.lang.Exception?) {
          boss.e("wifiConfigApplyFailed $e")
          finish(false)
        }

        override fun provisioningFailedFromDevice(failureReason: ESPConstants.ProvisionFailureReason?) {
          boss.e("provisioningFailedFromDevice $failureReason")
          finish(false)
        }

        override fun deviceProvisioningSuccess() {
          boss.d("deviceProvisioningSuccess")
          finish(true)
        }

        override fun onProvisioningFailed(e: java.lang.Exception?) {
          boss.e("onProvisioningFailed $e")
          finish(false)
        }

      })
    }
  }

}
class SendDataManager(boss: Boss) : ActionManager(boss) {
  override fun call(ctx: CallContext) {
    val guardedResult = ResultGuard(ctx.result)
    boss.d("sendDataToCustomEndPoint: start")
    val deviceName = ctx.arg("deviceName") ?: return
    val proofOfPossession = ctx.arg("proofOfPossession") ?: return
    val path = ctx.arg("path") ?: return
    val data = ctx.argBytes("data") ?: return
    val security = ctx.call.argument<String>("security")
    val conn = boss.connector(deviceName)
    if (conn == null) {
      guardedResult.error("E_DEVICE_NOT_FOUND", "BLE device is not available", "Device: $deviceName")
      return
    }

    boss.connect(conn, proofOfPossession, security, guardedResult::error) { esp ->
      boss.d("sendData: start")
      val handler = Handler(Looper.getMainLooper())
      var completed = false
      lateinit var timeoutRunnable: Runnable

      fun finish(action: () -> Unit) {
        if (completed) return
        completed = true
        handler.removeCallbacks(timeoutRunnable)
        try {
          esp.disconnectDevice()
        } catch (_: java.lang.Exception) {
        }
        handler.postDelayed({ action() }, 600)
      }

      timeoutRunnable = Runnable {
        boss.e("sendData: timeout")
        finish {
          guardedResult.error("E_SEND_DATA_TIMEOUT", "Send data timed out", "Device: $deviceName, path: $path")
        }
      }

      handler.postDelayed(timeoutRunnable, 10000)
      esp.sendDataToCustomEndPoint(path, data, object : ResponseListener {
        override fun onSuccess(returnData: ByteArray?) {
          boss.d("sendData: success")
          finish { guardedResult.success(returnData) }
        }

        override fun onFailure(e: java.lang.Exception?) {
          boss.e("sendData: failure $e")
          finish { guardedResult.error("E_SEND_DATA_FAILED", "Send data failed", "Exception details: $e") }
        }
      })
    }
  }
}

/** FlutterEspBleProvPlugin */
class FlutterEspBleProvPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.ActivityResultListener {

  private val logTag = "FlutterEspBleProvChannel"
  private val boss = Boss()
  private lateinit var channel: MethodChannel
  private var activityBinding: ActivityPluginBinding? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    Log.d(logTag, "onAttachedToEngine: $binding")
    channel = MethodChannel(binding.binaryMessenger, "flutter_esp_ble_prov")
    channel.setMethodCallHandler(this)
    boss.attachContext(binding.applicationContext)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    Log.d(logTag, "onDetachedFromEngine: $binding")
    channel.setMethodCallHandler(null)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    Log.d(logTag, "onMethodCall: ${call.method} ${call.arguments}")
    boss.call(call, result)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    Log.d(logTag, "onAttachedToActivity: $binding")
    init(binding)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    Log.d(logTag, "onDetachedFromActivityForConfigChanges")
    activityBinding?.let { tearDown(it) }
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    Log.d(logTag, "onReattachedToActivityForConfigChanges: $binding")
    init(binding)
  }

  override fun onDetachedFromActivity() {
    Log.d(logTag, "onDetachedFromActivity")
    activityBinding?.let { tearDown(it) }
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    Log.d(logTag, "onActivityResult $requestCode $resultCode $data")
    return false
  }

  private fun init(binding: ActivityPluginBinding) {
    activityBinding = binding;
    binding.addActivityResultListener(this)
    boss.attachBinding(binding)
    boss.attachActivity(binding.activity)
  }

  private fun tearDown(binding: ActivityPluginBinding) {
    binding.removeActivityResultListener(this)
    boss.detachBinding(binding)
    activityBinding = null;
  }
}

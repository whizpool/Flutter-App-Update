package com.example.flutter_app_update_lib

import android.app.Activity
import android.content.Intent
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/** FlutterAppUpdateLibPlugin */
class FlutterAppUpdateLibPlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {
    private lateinit var legacyChannel: MethodChannel
    private lateinit var updateMethodsChannel: MethodChannel
    private lateinit var updateEventsChannel: EventChannel

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var appUpdateManager: AppUpdateManager? = null
    private var appUpdateEventSink: EventChannel.EventSink? = null
    private var pendingUpdateResult: MethodChannel.Result? = null

    private val immediateUpdateRequestCode = 1001
    private val flexibleUpdateRequestCode = 1002

    private val installStateListener = InstallStateUpdatedListener { state ->
        appUpdateEventSink?.success(state.installStatus())
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        legacyChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_app_update_lib")
        updateMethodsChannel =
            MethodChannel(flutterPluginBinding.binaryMessenger, "de.ffuf.in_app_update/methods")
        updateEventsChannel =
            EventChannel(flutterPluginBinding.binaryMessenger, "de.ffuf.in_app_update/stateEvents")

        legacyChannel.setMethodCallHandler(this)
        updateMethodsChannel.setMethodCallHandler(this)
        updateEventsChannel.setStreamHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "checkForUpdate" -> handleCheckForUpdate(result)
            "performImmediateUpdate" ->
                handleStartUpdate(result, AppUpdateType.IMMEDIATE)
            "startFlexibleUpdate" ->
                handleStartUpdate(result, AppUpdateType.FLEXIBLE)
            "completeFlexibleUpdate" -> handleCompleteFlexibleUpdate(result)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        legacyChannel.setMethodCallHandler(null)
        updateMethodsChannel.setMethodCallHandler(null)
        updateEventsChannel.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        appUpdateEventSink = events
    }

    override fun onCancel(arguments: Any?) {
        appUpdateEventSink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        activityBinding?.addActivityResultListener(this)
        appUpdateManager = AppUpdateManagerFactory.create(binding.activity).also {
            it.registerListener(installStateListener)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != immediateUpdateRequestCode && requestCode != flexibleUpdateRequestCode) {
            return false
        }

        val pending = pendingUpdateResult
        pendingUpdateResult = null
        if (pending == null) return true

        if (resultCode == Activity.RESULT_OK) {
            pending.success(null)
        } else {
            pending.error(
                "USER_DENIED_UPDATE",
                "User denied or canceled in-app update flow.",
                null
            )
        }
        return true
    }

    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
        appUpdateManager?.unregisterListener(installStateListener)
        appUpdateManager = null
    }

    private fun handleCheckForUpdate(result: MethodChannel.Result) {
        val manager = appUpdateManager ?: run {
            result.error("IN_APP_UPDATE_FAILED", "Activity is not attached.", null)
            return
        }

        manager.appUpdateInfo
            .addOnSuccessListener { info ->
                result.success(serializeAppUpdateInfo(info))
            }
            .addOnFailureListener { error ->
                result.error("IN_APP_UPDATE_FAILED", error.message, null)
            }
    }

    private fun handleStartUpdate(
        result: MethodChannel.Result,
        updateType: Int
    ) {
        val manager = appUpdateManager ?: run {
            result.error("IN_APP_UPDATE_FAILED", "Activity is not attached.", null)
            return
        }
        val currentActivity = activity ?: run {
            result.error("IN_APP_UPDATE_FAILED", "Activity is not available.", null)
            return
        }

        if (pendingUpdateResult != null) {
            result.error("IN_APP_UPDATE_FAILED", "Another update flow is already active.", null)
            return
        }

        manager.appUpdateInfo
            .addOnSuccessListener { info ->
                val availability = info.updateAvailability()
                val allowed = info.isUpdateTypeAllowed(updateType)
                val updateAvailable =
                    availability == UpdateAvailability.UPDATE_AVAILABLE ||
                        availability == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS

                if (!updateAvailable || !allowed) {
                    result.error("IN_APP_UPDATE_FAILED", "Update not available or not allowed.", null)
                    return@addOnSuccessListener
                }

                try {
                    pendingUpdateResult = result
                    val options = AppUpdateOptions.newBuilder(updateType).build()
                    val requestCode =
                        if (updateType == AppUpdateType.IMMEDIATE) {
                            immediateUpdateRequestCode
                        } else {
                            flexibleUpdateRequestCode
                        }
                    manager.startUpdateFlowForResult(
                        info,
                        currentActivity,
                        options,
                        requestCode
                    )
                } catch (e: Exception) {
                    pendingUpdateResult = null
                    result.error("IN_APP_UPDATE_FAILED", e.message, null)
                }
            }
            .addOnFailureListener { error ->
                result.error("IN_APP_UPDATE_FAILED", error.message, null)
            }
    }

    private fun handleCompleteFlexibleUpdate(result: MethodChannel.Result) {
        val manager = appUpdateManager ?: run {
            result.error("IN_APP_UPDATE_FAILED", "Activity is not attached.", null)
            return
        }

        manager.completeUpdate()
            .addOnSuccessListener { result.success(null) }
            .addOnFailureListener { error ->
                result.error("IN_APP_UPDATE_FAILED", error.message, null)
            }
    }

    private fun serializeAppUpdateInfo(info: AppUpdateInfo): Map<String, Any?> {
        return mapOf(
            "updateAvailability" to mapUpdateAvailability(info.updateAvailability()),
            "immediateAllowed" to info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE),
            "immediateAllowedPreconditions" to emptyList<Int>(),
            "flexibleAllowed" to info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
            "flexibleAllowedPreconditions" to emptyList<Int>(),
            "availableVersionCode" to info.availableVersionCode(),
            "installStatus" to info.installStatus(),
            "packageName" to activity?.packageName,
            "clientVersionStalenessDays" to info.clientVersionStalenessDays(),
            "updatePriority" to info.updatePriority(),
        )
    }

    private fun mapUpdateAvailability(value: Int): Int {
        return when (value) {
            UpdateAvailability.UPDATE_NOT_AVAILABLE -> 1
            UpdateAvailability.UPDATE_AVAILABLE -> 2
            UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS -> 3
            else -> 0
        }
    }
}

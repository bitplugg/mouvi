package com.bitplugg.vpn_client

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * VpnService для VLESS-движка.
 *
 * WireGuard/AmneziaWG manage own VpnService внутри своих библиотек. VLESS
 * использует Xray только как SOCKS5-прокси, а этот сервис поднимает TUN,
 * применяет DNS/split tunneling и передаёт fd в tun2socks.
 */
class MouviVpnService : VpnService() {

    private val running = AtomicBoolean(false)
    private var tunnel: ParcelFileDescriptor? = null
    private var tun2socks: Process? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopTunnel()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> startTunnel(intent)
            else -> stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun startTunnel(intent: Intent) {
        if (!running.compareAndSet(false, true)) {
            return
        }
        try {
            startForeground(NOTIFICATION_ID, buildNotification(intent))

            val socksPort = intent.getIntExtra(EXTRA_SOCKS_PORT, XrayConfigBuilder.SOCKS_PORT)
            val dnsServers = intent.getStringExtra(EXTRA_DNS)?.parseDnsServers()
                ?.takeIf { it.isNotEmpty() }
                ?: listOf("1.1.1.1", "1.0.0.1")
            val excluded = intent.getStringArrayExtra(EXTRA_EXCLUDED).orEmpty().toList()
            val included = intent.getStringArrayExtra(EXTRA_INCLUDED).orEmpty().toList()

            val builder = Builder().apply {
                setSession("Mouvi VLESS")
                setMtu(MTU)
                addAddress(TUN_ADDRESS, 24)
                addAddress(TUN_ADDRESS_V6, 64)
                addRoute("0.0.0.0", 0)
                addRoute("::", 0)
                dnsServers.forEach(::addDnsServer)
                if (included.isNotEmpty()) {
                    included.forEach(::addAllowedApplication)
                } else {
                    excluded.forEach(::addDisallowedApplication)
                }
            }
            val descriptor = builder.establish()
                ?: throw IllegalStateException("VpnService.establish returned null")
            tunnel = descriptor

            // tun2socks получает TUN через stdin: ProcessBuilder сам создаст
            // новый fd в потомке, поэтому не нужно сбрасывать CLOEXEC вручную.
            val binary = File(filesDir, BINARY_TUN2SOCKS)
            if (!binary.exists()) {
                throw IllegalStateException("tun2socks binary is missing")
            }
            val command = listOf(
                binary.absolutePath,
                "-tunFd", "0",
                "-proxyServer", "127.0.0.1:$socksPort",
                "-tunAddr", TUN_ADDRESS,
                "-tunGw", TUN_GATEWAY,
                "-tunMask", "255.255.255.0",
                "-loglevel", "none",
            )
            val process = ProcessBuilder(command)
                .directory(filesDir)
                .redirectInput(ProcessBuilder.Redirect.from(File("/proc/self/fd/${descriptor.fd}")))
                .redirectErrorStream(true)
                .redirectOutput(ProcessBuilder.Redirect.appendTo(File(filesDir, "tun2socks.log")))
                .start()
            tun2socks = process
            VlessEngine.get(this).setServiceUp(true)
        } catch (_: Throwable) {
            stopTunnel()
            VlessEngine.get(this).setServiceUp(false)
            stopSelf()
        }
    }

    private fun stopTunnel() {
        if (!running.get()) {
            return
        }
        running.set(false)
        tun2socks?.destroy()
        tun2socks = null
        try {
            tunnel?.close()
        } catch (_: Throwable) {
        }
        tunnel = null
        VlessEngine.get(this).setServiceUp(false)
    }

    override fun onDestroy() {
        stopTunnel()
        super.onDestroy()
    }

    private fun buildNotification(intent: Intent): Notification {
        MouviNotifications(this).ensureChannel()
        val title = intent.getStringExtra(EXTRA_NAME).orEmpty().ifBlank { "Mouvi VLESS" }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_mouvi)
            .setContentTitle(title)
            .setContentText(intent.getStringExtra(EXTRA_PROTOCOL) ?: "VLESS")
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun String.parseDnsServers(): List<String> = split(',')
        .map { it.trim() }
        .filter { it.isNotEmpty() }

    companion object {
        const val ACTION_START = "com.bitplugg.vpn_client.VLESS_START"
        const val ACTION_STOP = "com.bitplugg.vpn_client.VLESS_STOP"
        const val EXTRA_SOCKS_PORT = "socksPort"
        const val EXTRA_DNS = "dns"
        const val EXTRA_EXCLUDED = "excluded"
        const val EXTRA_INCLUDED = "included"
        const val EXTRA_NAME = "name"
        const val EXTRA_PROTOCOL = "protocol"
        const val EXTRA_CONFIG_ID = "configId"

        internal const val BINARY_TUN2SOCKS = "tun2socks"
        internal const val TUN_ADDRESS = "10.55.0.2"
        internal const val TUN_GATEWAY = "10.55.0.1"
        internal const val TUN_ADDRESS_V6 = "fd00:mouvi::2"
        private const val MTU = 1500
        private const val CHANNEL_ID = "mouvi_connection"
        private const val NOTIFICATION_ID = 1002

        fun start(context: Context, intent: Intent) {
            intent.action = ACTION_START
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, MouviVpnService::class.java).setAction(ACTION_STOP)
            try {
                context.startService(intent)
            } catch (_: Throwable) {
                context.stopService(intent)
            }
        }
    }
}

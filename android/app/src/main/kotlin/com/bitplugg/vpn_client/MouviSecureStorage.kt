package com.bitplugg.vpn_client

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Шифрованное хранилище конфигураций.
 *
 * Ключ AES-256-GCM создаётся в Android Keystore и не покидает устройство.
 * В SharedPreferences лежит только base64(IV + ciphertext). При ошибке
 * расшифровки данные не удаляются автоматически — приложение просто
 * считает хранилище пустым, чтобы не терять пользовательские данные.
 */
object MouviSecureStorage {
    private const val PREFS_NAME = "mouvi_secure"
    private const val PREF_KEY = "configs_blob"
    private const val KEY_ALIAS = "mouvi_configs_key_v1"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128

    private fun prefs(context: Context) = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    @Synchronized
    fun read(context: Context): String? {
        val encoded = prefs(context).getString(PREF_KEY, null) ?: return null
        return try {
            val combined = Base64.decode(encoded, Base64.NO_WRAP)
            if (combined.size <= IV_BYTES) {
                return null
            }
            val iv = combined.copyOfRange(0, IV_BYTES)
            val ciphertext = combined.copyOfRange(IV_BYTES, combined.size)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(TAG_BITS, iv))
            String(cipher.doFinal(ciphertext), Charsets.UTF_8)
        } catch (_: Throwable) {
            // Повреждённые или зашифрованные другим ключом данные:
            // не удаляем их автоматически.
            null
        }
    }

    @Synchronized
    fun write(context: Context, data: String): Boolean {
        return try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
            val ciphertext = cipher.doFinal(data.toByteArray(Charsets.UTF_8))
            val combined = cipher.iv + ciphertext
            prefs(context).edit()
                .putString(PREF_KEY, Base64.encodeToString(combined, Base64.NO_WRAP))
                .commit()
        } catch (_: Throwable) {
            false
        }
    }

    @Synchronized
    fun clear(context: Context): Boolean {
        return prefs(context).edit().remove(PREF_KEY).commit()
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
        if (existing != null) {
            return existing.secretKey
        }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }
}

package eu.kanade.tachiyomi.extension.zh.mtldss

import android.content.SharedPreferences
import okhttp3.FormBody
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import org.jsoup.Jsoup
import java.io.IOException

class LoginInterceptor(private val preferences: SharedPreferences) : Interceptor {

    private val loginClient = OkHttpClient.Builder().build()

    @Throws(IOException::class)
    override fun intercept(chain: Interceptor.Chain): Response {
        val originalRequest = chain.request()

        // 检查是否需要登录
        if (!isLoggedIn()) {
            performLogin()
        }

        // 添加登录状态的请求头
        val cookies = getCookies()
        val newRequest = if (cookies.isNotEmpty()) {
            originalRequest.newBuilder()
                .addHeader("Cookie", cookies)
                .build()
        } else {
            originalRequest
        }

        return chain.proceed(newRequest)
    }

    private fun isLoggedIn(): Boolean {
        val cookies = preferences.getString(LOGIN_COOKIES_PREF, "")
        // 检查cookies是否包含登录状态标识
        return !cookies.isNullOrEmpty() && cookies.contains("wordpress_logged_in")
    }

    private fun performLogin(): Boolean {
        val username = preferences.getString(LOGIN_USERNAME_PREF, "")
        val password = preferences.getString(LOGIN_PASSWORD_PREF, "")

        if (username.isNullOrEmpty() || password.isNullOrEmpty()) {
            return false
        }

        try {
            val baseUrl = "https://mtldss.top"

            // 第一步：访问用户页面获取初始cookies和可能的nonce
            val userPageRequest = Request.Builder()
                .url("$baseUrl/user/")
                .addHeader("Referer", baseUrl)
                .addHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                .build()

            val userPageResponse = loginClient.newCall(userPageRequest).execute()
            if (!userPageResponse.isSuccessful) {
                return false
            }

            // 提取初始cookies
            val initialCookies = userPageResponse.headers("Set-Cookie")
                .map { it.substringBefore(";") }
                .joinToString("; ")

            // 解析页面获取可能的nonce或其他隐藏字段
            val userPageDoc = Jsoup.parse(userPageResponse.body?.string() ?: "")

            // 第二步：构建登录请求
            val loginBody = FormBody.Builder()
                .add("username", username)
                .add("password", password)
                .add("action", "user_signin")
                .add("remember", "forever")
                .add("captcha_mode", "slider") // 根据HTML结构添加
                .build()

            // 发送登录请求到AJAX端点
            val loginRequest = Request.Builder()
                .url("$baseUrl/wp-admin/admin-ajax.php")
                .post(loginBody)
                .addHeader("Content-Type", "application/x-www-form-urlencoded")
                .addHeader("X-Requested-With", "XMLHttpRequest")
                .addHeader("Referer", "$baseUrl/user/")
                .addHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                .apply {
                    if (initialCookies.isNotEmpty()) {
                        addHeader("Cookie", initialCookies)
                    }
                }
                .build()

            val loginResponse = loginClient.newCall(loginRequest).execute()

            if (loginResponse.isSuccessful) {
                val responseBody = loginResponse.body?.string() ?: ""

                // 检查登录响应是否成功
                if (responseBody.contains("success") || responseBody.contains("登录成功")) {
                    // 合并所有cookies
                    val allCookies = mutableListOf<String>()

                    // 添加初始cookies
                    if (initialCookies.isNotEmpty()) {
                        allCookies.addAll(initialCookies.split("; "))
                    }

                    // 添加登录响应的cookies
                    loginResponse.headers("Set-Cookie").forEach { cookie ->
                        allCookies.add(cookie.substringBefore(";"))
                    }

                    val finalCookies = allCookies.distinct().joinToString("; ")

                    if (finalCookies.isNotEmpty()) {
                        preferences.edit()
                            .putString(LOGIN_COOKIES_PREF, finalCookies)
                            .apply()
                        return true
                    }
                }
            }

            return false
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }

    private fun getCookies(): String {
        return preferences.getString(LOGIN_COOKIES_PREF, "") ?: ""
    }

    companion object {
        const val LOGIN_USERNAME_PREF = "login_username"
        const val LOGIN_PASSWORD_PREF = "login_password"
        const val LOGIN_COOKIES_PREF = "login_cookies"
    }
}

package eu.kanade.tachiyomi.extension.zh.mtldss

import android.content.Context
import android.content.SharedPreferences
import androidx.preference.EditTextPreference
import androidx.preference.ListPreference

const val LOGIN_USERNAME_PREF = "login_username"
const val LOGIN_PASSWORD_PREF = "login_password"
const val LOGIN_COOKIES_PREF = "login_cookies"

internal fun getPreferenceList(context: Context, preferences: SharedPreferences, isUrlUpdated: Boolean) = arrayOf(
    EditTextPreference(context).apply {
        key = LOGIN_USERNAME_PREF
        title = "登录用户名"
        summary = "输入您的用户名或邮箱地址"
        setDefaultValue("")
    },

    EditTextPreference(context).apply {
        key = LOGIN_PASSWORD_PREF
        title = "登录密码"
        summary = "输入您的登录密码"
        setDefaultValue("")
        setOnBindEditTextListener { editText ->
            editText.inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
        }
    },

    ListPreference(context).apply {
        key = MAINSITE_RATELIMIT_PREF
        title = "在限制时间内（下个设置项）允许的请求数量。"
        entries = Array(10) { "${it + 1}" }
        entryValues = Array(10) { "${it + 1}" }
        summary = "此值影响更新书架时发起连接请求的数量。调低此值可能减小IP被屏蔽的几率，但加载速度也会变慢。需要重启软件以生效。\n当前值：%s"

        setDefaultValue(MAINSITE_RATELIMIT_PREF_DEFAULT)
    },

    ListPreference(context).apply {
        key = MAINSITE_RATELIMIT_PERIOD
        title = "限制持续时间。单位秒"
        entries = Array(60) { "${it + 1}" }
        entryValues = Array(60) { "${it + 1}" }
        summary = "此值影响更新书架时请求的间隔时间。调大此值可能减小IP被屏蔽的几率，但更新时间也会变慢。需要重启软件以生效。\n当前值：%s"

        setDefaultValue(MAINSITE_RATELIMIT_PERIOD_DEFAULT)
    },

    EditTextPreference(context).apply {
        key = BLOCK_PREF
        title = "屏蔽词列表"
        setDefaultValue(
            "// 例如 \"YAOI cos 扶他 毛絨絨 獵奇 韩漫 韓漫\", " +
                "关键词之间用空格分离, 大小写不敏感, \"//\"后的字符会被忽略",
        )
        dialogTitle = "关键词列表"
    },
)

// 固定使用 mtldss.top 域名
val SharedPreferences.baseUrl: String
    get() = "mtldss.top"

internal const val BLOCK_PREF = "BLOCK_GENRES_LIST"

internal const val MAINSITE_RATELIMIT_PREF = "mainSiteRateLimitPreference"
internal const val MAINSITE_RATELIMIT_PREF_DEFAULT = 1.toString()

internal const val MAINSITE_RATELIMIT_PERIOD = "mainSiteRateLimitPeriodPreference"
internal const val MAINSITE_RATELIMIT_PERIOD_DEFAULT = 3.toString()

fun SharedPreferences.preferenceMigration() {
    // 清理旧的镜像设置
    edit()
        .remove("overrideBaseUrl")
        .remove("useMirrorWebsitePreference")
        .remove("defaultBaseUrlList")
        .remove("baseUrlList")
        .apply()
}

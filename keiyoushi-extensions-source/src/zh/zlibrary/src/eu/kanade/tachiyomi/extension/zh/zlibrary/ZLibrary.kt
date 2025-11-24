package eu.kanade.tachiyomi.extension.zh.zlibrary

import android.app.Application
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.preference.ListPreference
import androidx.preference.PreferenceScreen
import androidx.preference.SwitchPreferenceCompat
import eu.kanade.tachiyomi.network.GET
import eu.kanade.tachiyomi.source.ConfigurableSource
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.online.HttpSource
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import org.jsoup.Jsoup
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import uy.kohesive.injekt.injectLazy
import java.nio.charset.Charset
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class ZLibrary : HttpSource(), ConfigurableSource {

    override val name = "Z-Library"
    override val lang = "zh"
    override val supportsLatest = true

    private val preferences: SharedPreferences by lazy {
        Injekt.get<Application>().getSharedPreferences("source_$id", 0x0000)
    }

    // 域名配置 - 支持的Z-Library域名
    private val domains = arrayOf(
        "zh.101istp.ru",
        "zh.z-library.sk",
        "z-lib.ai",
        "z-library.cc",
    )

    private val domainNames = arrayOf(
        "Z-Library RU (zh.101istp.ru) - 国内可访问",
        "Z-Library 主站 (zh.z-library.sk)",
        "Z-Lib AI (z-lib.ai)",
        "Z-Library CC (z-library.cc)",
    )

    override val baseUrl: String
        get() {
            val selectedDomain = preferences.getString(PREF_DOMAIN_KEY, domains[0])!!
            return "https://$selectedDomain"
        }

    // 访问模式配置 - 只有主站支持API模式，其他分站强制使用WebView
    private val useApiMode: Boolean
        get() {
            // 完全禁用API模式，强制使用WebView模式
            return false
        }

    private val json: Json by injectLazy()

    // 获取正确编码的响应内容
    private fun getResponseBodyWithCorrectEncoding(response: Response): String {
        val responseBody = response.body
        val contentType = response.header("Content-Type")

        // 检查Content-Type中是否指定了字符集
        val charset = when {
            contentType?.contains("charset=utf-8", ignoreCase = true) == true -> Charsets.UTF_8
            contentType?.contains("charset=gbk", ignoreCase = true) == true -> Charset.forName("GBK")
            contentType?.contains("charset=gb2312", ignoreCase = true) == true -> Charset.forName("GB2312")
            else -> {
                // 默认使用UTF-8，这是现代网站的标准
                Charsets.UTF_8
            }
        }

        return try {
            // 使用指定的字符集读取响应内容
            responseBody.source().readString(charset)
        } catch (e: Exception) {
            // 如果指定字符集失败，尝试UTF-8
            try {
                responseBody.source().readString(Charsets.UTF_8)
            } catch (e2: Exception) {
                // 最后尝试默认字符集
                responseBody.string()
            }
        }
    }

    // Cookie拦截器用于WebView模式 - 根据当前域名动态创建
    override val client: OkHttpClient = network.cloudflareClient.newBuilder()
        .addInterceptor(::authInterceptor)
        .build()

    private fun authInterceptor(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val response = chain.proceed(request)

        // 检查是否需要登录或域名不可用
        if (response.code == 401 || response.code == 403) {
            response.close()
            throw Exception("请在 WebView 中登录 Z-Library 或尝试切换域名")
        }

        if (response.code == 404 || response.code >= 500) {
            response.close()
            throw Exception("当前域名 ${baseUrl.toHttpUrl().host} 可能不可用，请尝试切换其他域名")
        }

        val responseBody = response.peekBody(1024).string()
        if (responseBody.contains("login") || responseBody.contains("sign in")) {
            response.close()
            throw Exception("需要登录，请在 WebView 模式下登录 Z-Library")
        }

        return response
    }

    override fun headersBuilder() = super.headersBuilder()
        .add("Referer", "$baseUrl/")
        .add("User-Agent", "Mozilla/5.0 (Linux; Android 14; SM-F936U1 Build/UP1A.231005.007) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.6422.34 Safari/537.36")
        .add("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8")
        .add("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
        .add("Accept-Encoding", "gzip, deflate, br")
        .add("DNT", "1")
        .add("Connection", "keep-alive")
        .add("Upgrade-Insecure-Requests", "1")
        .add("Sec-Fetch-Dest", "document")
        .add("Sec-Fetch-Mode", "navigate")
        .add("Sec-Fetch-Site", "none")
        .add("Cache-Control", "max-age=0")

    // 热门书籍
    override fun popularMangaRequest(page: Int): Request {
        println("ZLibrary Debug - 创建热门请求: page=$page, baseUrl=$baseUrl (WebView模式)")

        // 只使用WebView模式 - 热门内容在主页上
        if (page == 1) {
            // 第一页访问主页，解析其中的热门推荐部分
            println("ZLibrary Debug - 访问主页: $baseUrl")
            return GET(baseUrl, headers)
        } else {
            // 后续页面直接返回空结果，因为我们将使用WebView处理分页
            println("ZLibrary Debug - WebView模式不支持分页，返回第一页")
            return GET(baseUrl, headers)
        }
    }

    override fun popularMangaParse(response: Response): MangasPage {
        return parseWebResponse(response)
    }

    // 最新更新
    override fun latestUpdatesRequest(page: Int): Request {
        val recentPath = when (baseUrl.toHttpUrl().host) {
            "zh.z-library.sk" -> "/recent"
            "z-lib.ai" -> "/recently-added"
            else -> "/recent"
        }
        return GET("$baseUrl$recentPath?page=$page", headers)
    }

    override fun latestUpdatesParse(response: Response) = popularMangaParse(response)

    // 搜索
    override fun searchMangaRequest(page: Int, query: String, filters: FilterList): Request {
        // 直接构造搜索URL，使用URL编码的查询字符串
        val encodedQuery = java.net.URLEncoder.encode(query, "UTF-8")
        val searchUrl = "$baseUrl/s/$encodedQuery"
        val url = searchUrl.toHttpUrl().newBuilder()
        if (page > 1) {
            url.addQueryParameter("page", page.toString())
        }
        return GET(url.build().toString(), headers)
    }

    override fun searchMangaParse(response: Response): MangasPage {
        // WebView模式：解析搜索结果页面
        val document = Jsoup.parse(getResponseBodyWithCorrectEncoding(response))
        val mangaList = mutableListOf<SManga>()

        // 查找搜索结果中的书籍项目
        val bookItems = document.select("div.book-item.resItemBoxBooks")

        bookItems.forEach { item ->
            try {
                val manga = parseSearchBookItem(item)
                if (manga != null) {
                    mangaList.add(manga)
                }
            } catch (e: Exception) {
                // 跳过解析失败的单个元素
            }
        }

        // 检查是否有下一页
        val hasNextPage = document.selectFirst("a[rel=next]") != null ||
            document.selectFirst(".pagination .next") != null ||
            document.selectFirst("a:contains(下一页)") != null

        return MangasPage(mangaList, hasNextPage)
    }

    // 书籍详情
    override fun mangaDetailsRequest(manga: SManga): Request {
        // 为详情页请求创建专门的headers，设置正确的Referer
        val detailHeaders = headers.newBuilder()
            .set("Referer", baseUrl)
            .build()

        // 只使用WebView模式 - 直接使用完整URL
        return if (manga.url.startsWith("http")) {
            GET(manga.url, detailHeaders)
        } else {
            GET("$baseUrl${manga.url}", detailHeaders)
        }
    }

    override fun mangaDetailsParse(response: Response): SManga {
        return parseWebMangaDetails(response)
    }

    // 章节列表（对于书籍，通常只有一个章节）
    override fun chapterListRequest(manga: SManga): Request {
        return mangaDetailsRequest(manga)
    }

    override fun chapterListParse(response: Response): List<SChapter> {
        val chapter = SChapter.create().apply {
            url = response.request.url.toString()
            name = "阅读"
            chapter_number = 1f
        }
        return listOf(chapter)
    }

    // 页面列表（下载链接）
    override fun pageListRequest(chapter: SChapter): Request {
        // 从完整URL中提取bookId
        val bookId = if (chapter.url.contains("/book/")) {
            chapter.url.substringAfterLast("/book/").substringBefore("/")
        } else {
            chapter.url.substringAfterLast("/")
        }
        // 只使用WebView模式
        return GET("$baseUrl/book/$bookId/download", headers)
    }

    override fun pageListParse(response: Response): List<Page> {
        return parseWebDownloadLink(response)
    }

    // 专门处理在线阅读页面的图片解析
    private fun parseReaderPage(readerUrl: String): List<Page> {
        return try {
            val request = GET(readerUrl, headers)
            val response = client.newCall(request).execute()

            if (!response.isSuccessful) {
                throw Exception("无法访问阅读页面: ${response.code}")
            }

            val document = Jsoup.parse(getResponseBodyWithCorrectEncoding(response))
            val pages = mutableListOf<Page>()

            // 尝试多种图片选择器来获取所有页面图片
            val imageSelectors = listOf(
                "img[src*='.jpg']",
                "img[src*='.jpeg']", "img[src*='.png']",
                "img[src*='.gif']",
                "img[src*='.webp']",
                "canvas + img",
                ".page-image img",
                ".reader-image img",
                "#reader img",
                ".content img",
                "img[data-src]",
                "img.lazy",
                "img[loading='lazy']",
                ".page img",
                ".book-page img",
            )

            var pageIndex = 0
            for (selector in imageSelectors) {
                val imgElements = document.select(selector)
                for (imgElement in imgElements) {
                    val imgSrc = imgElement.attr("src") ?: imgElement.attr("data-src")
                    if (!imgSrc.isNullOrEmpty() && !imgSrc.contains("icon") && !imgSrc.contains("logo") &&
                        !imgSrc.contains("avatar")
                    ) {
                        val fullImageUrl = if (imgSrc.startsWith("/")) {
                            baseUrl + imgSrc
                        } else if (imgSrc.startsWith("http")) {
                            imgSrc
                        } else {
                            baseUrl + "/" + imgSrc
                        }

                        pages.add(Page(pageIndex++, readerUrl, fullImageUrl))
                    }
                }
                if (pages.isNotEmpty()) break // 如果找到图片就停止尝试其他选择器
            }

            // 如果没有找到图片，可能是JavaScript动态加载的
            if (pages.isEmpty()) {
                // 返回一个特殊的Page，让Tachiyomi使用WebView加载
                pages.add(Page(0, readerUrl, ""))
            }

            pages
        } catch (e: Exception) {
            throw Exception("解析阅读页面失败: ${e.message}")
        }
    }

    override fun imageUrlParse(response: Response): String {
        // 对于在线阅读页面，需要解析页面中的图片
        val document = Jsoup.parse(getResponseBodyWithCorrectEncoding(response))

        // 尝试多种图片选择器
        val imageSelectors = listOf(
            "img[src*='.jpg']",
            "img[src*='.jpeg']", "img[src*='.png']",
            "img[src*='.gif']",
            "img[src*='.webp']",
            "canvas + img",
            ".page-image img",
            ".reader-image img",
            "#reader img",
            ".content img",
            "img[data-src]",
            "img.lazy",
            "img[loading='lazy']",
        )

        for (selector in imageSelectors) {
            val imgElements = document.select(selector)
            for (imgElement in imgElements) {
                val imgSrc = imgElement.attr("src") ?: imgElement.attr("data-src")
                if (!imgSrc.isNullOrEmpty() && !imgSrc.contains("icon") && !imgSrc.contains("logo")) {
                    return if (imgSrc.startsWith("/")) {
                        baseUrl + imgSrc
                    } else if (imgSrc.startsWith("http")) {
                        imgSrc
                    } else {
                        baseUrl + "/" + imgSrc
                    }
                }
            }
        }

        // 如果没有找到图片，可能需要等待JavaScript加载
        // 返回页面URL，让Tachiyomi使用WebView加载
        return response.request.url.toString()
    }

    // 移除parseApiResponse方法，只使用WebView模式

    // 页面结构检测方法 - 智能识别页面类型并选择合适的解析策略
    private fun detectPageStructure(document: Document): String {
        return when {
            // 检测新版主页结构
            document.selectFirst("#booksMosaicBoxContainer .masonry-endless") != null -> {
                println("ZLibrary Debug - 检测到页面结构: mosaic (新版主页)")
                "mosaic"
            }
            // 检测推荐部分
            document.selectFirst(".recommendations") != null -> {
                println("ZLibrary Debug - 检测到页面结构: recommendations (推荐部分)")
                "recommendations"
            }
            // 检测Z-Cover结构
            document.selectFirst(".z-cover") != null -> {
                println("ZLibrary Debug - 检测到页面结构: z-cover (Z-Cover结构)")
                "z-cover"
            }
            // 检测通用masonry结构
            document.selectFirst(".masonry") != null -> {
                println("ZLibrary Debug - 检测到页面结构: masonry (通用masonry)")
                "masonry"
            }
            // 检测登录页面
            document.selectFirst("form[action*='login']") != null -> {
                println("ZLibrary Debug - 检测到页面结构: login (登录页面)")
                "login"
            }
            // 检测验证码页面
            document.selectFirst(".captcha, #captcha") != null -> {
                println("ZLibrary Debug - 检测到页面结构: captcha (验证码页面)")
                "captcha"
            }
            // 检测是否有书籍链接
            document.select("a[href*='/book/'], a[href*='/s/']").isNotEmpty() -> {
                println("ZLibrary Debug - 检测到页面结构: generic (通用书籍页面)")
                "generic"
            }
            else -> {
                println("ZLibrary Debug - 检测到页面结构: unknown (未知结构)")
                "unknown"
            }
        }
    }

    // WebView响应解析 - 改进HTML解析，支持懒加载
    private fun parseWebResponse(response: Response): MangasPage {
        return try {
            val requestUrl = response.request.url.toString()
            println("ZLibrary Debug - 解析Web响应: URL=$requestUrl, 状态码=${response.code}")

            // 检查HTTP状态码
            if (!response.isSuccessful) {
                val errorMsg = when (response.code) {
                    403 -> "访问被拒绝 (403) - 可能需要登录或被封禁"
                    404 -> "页面未找到 (404) - 请检查域名是否正确"
                    429 -> "请求过于频繁 (429) - 请稍后再试"
                    500 -> "服务器内部错误 (500) - Z-Library服务器问题"
                    502, 503 -> "服务器暂时不可用 (${response.code}) - 请稍后再试"
                    else -> "HTTP错误 (${response.code}): ${response.message}"
                }
                throw Exception("$errorMsg\n当前域名: ${baseUrl.toHttpUrl().host}")
            }

            // 移除AJAX处理逻辑，只使用WebView模式

            // 对于主页和搜索结果页面，使用WebView等待懒加载
            val responseBody = if (!useApiMode && (
                requestUrl == baseUrl || requestUrl.contains("/search") || requestUrl.contains("/popular") || requestUrl.contains("/most-popular") || requestUrl.contains("/recent") || requestUrl.contains("/page/")
                )
            ) {
                try {
                    // 等待懒加载完成，特别是封面图片
                    waitForLazyLoading(requestUrl, 2000)
                } catch (e: Exception) {
                    // WebView降级机制：如果WebView加载失败，降级到直接HTML解析
                    println("ZLibrary Debug - WebView加载失败，降级到直接HTML解析: ${e.message}")
                    getResponseBodyWithCorrectEncoding(response)
                }
            } else {
                getResponseBodyWithCorrectEncoding(response)
            }

            val document = Jsoup.parse(responseBody)
            val mangaList = mutableListOf<SManga>()
            println("ZLibrary Debug - HTML文档解析完成，长度: ${responseBody.length}")

            // 智能检测页面结构
            val pageStructure = detectPageStructure(document)

            // 根据页面结构选择合适的解析策略
            when (pageStructure) {
                "login" -> {
                    throw Exception("页面被重定向到登录页面 - 可能需要登录或Cookie已过期\n当前域名: ${baseUrl.toHttpUrl().host}")
                }
                "captcha" -> {
                    throw Exception("页面显示验证码 - 可能被识别为机器人访问\n当前域名: ${baseUrl.toHttpUrl().host}")
                }
                "unknown" -> {
                    throw Exception("页面结构未知 - 可能网站结构已更新\n当前域名: ${baseUrl.toHttpUrl().host}")
                }
            }

            // 如果是主页请求，使用智能解析策略
            if (requestUrl == baseUrl) {
                println("ZLibrary Debug - 解析主页内容，页面结构: $pageStructure")
                parseHomepageByStructure(document, pageStructure, mangaList)
            } else {
                // 非主页请求的解析逻辑保持不变
                parseNonHomepageContent(document, mangaList)
            }

            return MangasPage(mangaList, false)
        } catch (e: Exception) {
            println("ZLibrary Debug - 解析响应时发生错误: ${e.message}")
            throw e
        }
    }

    // 根据页面结构解析主页内容
    private fun parseHomepageByStructure(document: Document, pageStructure: String, mangaList: MutableList<SManga>) {
        when (pageStructure) {
            "mosaic" -> {
                // 解析新版主页结构
                val mosaicContainer = document.selectFirst("#booksMosaicBoxContainer .masonry-endless")!!
                val bookItems = mosaicContainer.select(".item")
                println("ZLibrary Debug - 在mosaic结构中找到 ${bookItems.size} 个.item元素")

                bookItems.take(20).forEach { item ->
                    try {
                        val bookLinks = item.select("a[href*='/book/'], a[href*='/s/']")
                        bookLinks.forEach { link ->
                            val manga = parsePopularBookItem(link)
                            if (manga != null) {
                                mangaList.add(manga)
                                println("ZLibrary Debug - 从mosaic成功解析书籍: ${manga.title}")
                            }
                        }
                    } catch (e: Exception) {
                        println("ZLibrary Debug - 解析mosaic书籍失败: ${e.message}")
                    }
                }
            }
            "recommendations" -> {
                // 解析推荐部分
                val recommendationsSection = document.selectFirst(".recommendations")!!
                val bookLinks = recommendationsSection.select("a[href*='/book/'], a[href*='/s/']")
                println("ZLibrary Debug - 推荐部分找到 ${bookLinks.size} 个书籍链接")

                bookLinks.forEach { link ->
                    try {
                        val manga = parsePopularBookItem(link)
                        if (manga != null) {
                            mangaList.add(manga)
                            println("ZLibrary Debug - 从推荐部分成功解析书籍: ${manga.title}")
                        }
                    } catch (e: Exception) {
                        println("ZLibrary Debug - 解析推荐书籍失败: ${e.message}")
                    }
                }
            }
            "z-cover", "masonry", "generic" -> {
                // 使用通用解析策略
                parseGenericBookLinks(document, mangaList)
            }
        }
    }

    // 解析通用书籍链接
    private fun parseGenericBookLinks(document: Document, mangaList: MutableList<SManga>) {
        val allBookLinks = document.select("a[href*='/book/'], a[href*='/s/']")
        println("ZLibrary Debug - 使用通用策略，找到 ${allBookLinks.size} 个书籍链接")

        allBookLinks.take(20).forEach { link ->
            try {
                val manga = parsePopularBookItem(link)
                if (manga != null) {
                    mangaList.add(manga)
                    println("ZLibrary Debug - 通用策略成功解析书籍: ${manga.title}")
                }
            } catch (e: Exception) {
                println("ZLibrary Debug - 通用策略解析书籍失败: ${e.message}")
            }
        }
    }

    // 解析非主页内容
    private fun parseNonHomepageContent(document: Document, mangaList: MutableList<SManga>) {
        // 首先尝试解析Most Popular部分的masonry-endless容器
        val masonryContainer = document.selectFirst(".masonry-endless")
        if (masonryContainer != null) {
            val bookItems = masonryContainer.select("div.item")
            bookItems.forEach { item ->
                try {
                    val manga = parsePopularBookItem(item)
                    if (manga != null) {
                        mangaList.add(manga)
                    }
                } catch (e: Exception) {
                    // 跳过解析失败的单个元素，继续处理其他元素
                }
            }
        }

        // 如果masonry-endless没有找到内容，优先使用z-cover和z-bookcard元素
        if (mangaList.isEmpty()) {
            // 首先尝试解析z-cover元素（主页推荐书籍）
            val zCoverElements = document.select("z-cover")
            if (zCoverElements.isNotEmpty()) {
                println("ZLibrary Debug - 找到 ${zCoverElements.size} 个z-cover元素")
                zCoverElements.forEach { zCover ->
                    try {
                        val manga = parsePopularBookItem(zCover)
                        if (manga != null) {
                            mangaList.add(manga)
                        }
                    } catch (e: Exception) {
                        println("ZLibrary Debug - 解析z-cover元素失败: ${e.message}")
                    }
                }
            }

            // 如果z-cover没有找到内容，尝试z-bookcard元素
            if (mangaList.isEmpty()) {
                val zBookcardElements = document.select("z-bookcard")
                if (zBookcardElements.isNotEmpty()) {
                    println("ZLibrary Debug - 找到 ${zBookcardElements.size} 个z-bookcard元素")
                    zBookcardElements.forEach { zBookcard ->
                        try {
                            val manga = parseSearchBookItem(zBookcard)
                            if (manga != null) {
                                mangaList.add(manga)
                            }
                        } catch (e: Exception) {
                            println("ZLibrary Debug - 解析z-bookcard元素失败: ${e.message}")
                        }
                    }
                }
            }

            // 最后回退到传统选择器（优化版本）
            if (mangaList.isEmpty()) {
                // 首先尝试更广泛的选择器，包括可能的JavaScript渲染内容
                val allPossibleSelectors = listOf(
                    // 传统选择器
                    ".book-item", ".book", ".item", "[data-book-id]", ".search-result",
                    // 可能的容器选择器
                    ".resItemBox", ".bookRow", ".result-item", ".book-card",
                    // 链接选择器（可能包含书籍）
                    "a[href*='/book/']", "a[href*='/s/']",
                    // 通用容器选择器
                    ".container .row > div", ".grid-item", ".list-item",
                    // 可能的JavaScript生成内容
                    "[data-book]", "[data-id]", ".book-container",
                )

                val bookElements = document.select(allPossibleSelectors.joinToString(", "))
                println("ZLibrary Debug - 扩展选择器找到 ${bookElements.size} 个元素")

                if (bookElements.isNotEmpty()) {
                    bookElements.mapNotNullTo(mangaList) { element ->
                        try {
                            parsePopularBookItem(element)
                        } catch (e: Exception) {
                            println("ZLibrary Debug - 解析元素失败: ${e.message}")
                            null // 跳过解析失败的单个元素
                        }
                    }
                }

                // 如果仍然没有找到，尝试解析所有包含链接的元素
                if (mangaList.isEmpty()) {
                    val allLinks = document.select("a[href*='/book/'], a[href*='/s/']")
                    println("ZLibrary Debug - 尝试解析所有书籍链接: ${allLinks.size} 个")

                    allLinks.mapNotNullTo(mangaList) { link ->
                        try {
                            parsePopularBookItem(link)
                        } catch (e: Exception) {
                            println("ZLibrary Debug - 解析链接失败: ${e.message}")
                            null
                        }
                    }
                }
            }
        }

        return MangasPage(mangaList, false)
    }

    private fun parseNonHomepageContent(document: Document, mangaList: MutableList<SManga>) {
        // 首先尝试解析Most Popular部分的masonry-endless容器（非主页情况）
        val masonryContainer = document.selectFirst(".masonry-endless")
        if (masonryContainer != null) {
            val bookItems = masonryContainer.select("div.item")
            bookItems.forEach { item ->
                try {
                    val manga = parsePopularBookItem(item)
                    if (manga != null) {
                        mangaList.add(manga)
                    }
                } catch (e: Exception) {
                    // 跳过解析失败的单个元素，继续处理其他元素
                }
            }
        }

        // 如果masonry-endless没有找到内容，优先使用z-cover和z-bookcard元素
        if (mangaList.isEmpty()) {
            // 首先尝试解析z-cover元素（主页推荐书籍）
            val zCoverElements = document.select("z-cover")
            if (zCoverElements.isNotEmpty()) {
                println("ZLibrary Debug - 找到 ${zCoverElements.size} 个z-cover元素")
                zCoverElements.forEach { zCover ->
                    try {
                        val manga = parsePopularBookItem(zCover)
                        if (manga != null) {
                            mangaList.add(manga)
                        }
                    } catch (e: Exception) {
                        println("ZLibrary Debug - 解析z-cover元素失败: ${e.message}")
                    }
                }
            }

            // 如果z-cover没有找到内容，尝试z-bookcard元素
            if (mangaList.isEmpty()) {
                val zBookcardElements = document.select("z-bookcard")
                if (zBookcardElements.isNotEmpty()) {
                    println("ZLibrary Debug - 找到 ${zBookcardElements.size} 个z-bookcard元素")
                    zBookcardElements.forEach { zBookcard ->
                        try {
                            val manga = parseSearchBookItem(zBookcard)
                            if (manga != null) {
                                mangaList.add(manga)
                            }
                        } catch (e: Exception) {
                            println("ZLibrary Debug - 解析z-bookcard元素失败: ${e.message}")
                        }
                    }
                }
            }

            // 最后回退到传统选择器（优化版本）
            if (mangaList.isEmpty()) {
                // 首先尝试更广泛的选择器，包括可能的JavaScript渲染内容
                val allPossibleSelectors = listOf(
                    // 传统选择器
                    ".book-item", ".book", ".item", "[data-book-id]", ".search-result",
                    // 可能的容器选择器
                    ".resItemBox", ".bookRow", ".result-item", ".book-card",
                    // 链接选择器（可能包含书籍）
                    "a[href*='/book/']", "a[href*='/s/']",
                    // 通用容器选择器
                    ".container .row > div", ".grid-item", ".list-item",
                    // 可能的JavaScript生成内容
                    "[data-book]", "[data-id]", ".book-container",
                )

                val bookElements = document.select(allPossibleSelectors.joinToString(", "))
                println("ZLibrary Debug - 扩展选择器找到 ${bookElements.size} 个元素")

                if (bookElements.isNotEmpty()) {
                    bookElements.mapNotNullTo(mangaList) { element ->
                        try {
                            parsePopularBookItem(element)
                        } catch (e: Exception) {
                            println("ZLibrary Debug - 解析元素失败: ${e.message}")
                            null // 跳过解析失败的单个元素
                        }
                    }
                }

                // 如果仍然没有找到，尝试解析所有包含链接的元素
                if (mangaList.isEmpty()) {
                    val allLinks = document.select("a[href*='/book/'], a[href*='/s/']")
                    println("ZLibrary Debug - 尝试解析所有书籍链接: ${allLinks.size} 个")

                    allLinks.mapNotNullTo(mangaList) { link ->
                        try {
                            // 尝试从链接的父元素或链接本身解析书籍信息
                            val parentElement = link.parent() ?: link
                            parsePopularBookItem(parentElement)
                        } catch (e: Exception) {
                            println("ZLibrary Debug - 解析链接失败: ${e.message}")
                            null
                        }
                    }
                }
            }
        }
    }

    // WebView漫画详情解析 - 基于实际HTML结构优化，支持懒加载
    private fun parseWebMangaDetails(response: Response): SManga {
        return try {
            val requestUrl = response.request.url.toString()

            // 对于详情页面，使用WebView等待懒加载完成
            val responseBody = if (!useApiMode) {
                // 等待懒加载完成，特别是封面图片和描述内容
                waitForLazyLoading(requestUrl, 3000)
            } else {
                getResponseBodyWithCorrectEncoding(response)
            }

            val document = Jsoup.parse(responseBody)

            // 检查页面是否正常加载
            if (responseBody.contains("404") || responseBody.contains("Not Found") || responseBody.contains("页面不存在") || responseBody.contains("Book not found")) {
                throw Exception("书籍不存在或已被删除 (404错误) - URL: $requestUrl")
            }

            if (responseBody.contains("Access denied") || responseBody.contains("访问被拒绝") ||
                responseBody.contains("Forbidden") || responseBody.contains("403")
            ) {
                throw Exception("访问被拒绝，可能需要登录或该域名被限制 - 当前域名: ${baseUrl.toHttpUrl().host}")
            }

            if (responseBody.contains("Too many requests") || responseBody.contains("请求过多") ||
                responseBody.contains("Rate limit") || responseBody.contains("429")
            ) {
                throw Exception("请求频率过高，请稍后重试或切换域名 - 当前域名: ${baseUrl.toHttpUrl().host}")
            }

            SManga.create().apply {
                var titleFound = false
                var authorFound = false
                var descriptionFound = false

                // 标题解析 - 基于实际HTML结构：<h1 class="book-title" itemprop="name">
                val titleSelectors = listOf(
                    "h1.book-title[itemprop=name]",
                    "h1.book-title",
                    "h1[itemprop=name]",
                    "h1",
                    ".book-title",
                    ".title",
                    ".main-title",
                    "[data-title]",
                    ".book-info h1",
                    ".detail-title",
                    ".bookDetailsBox h1",
                )

                for (selector in titleSelectors) {
                    val titleElement = document.selectFirst(selector)
                    if (titleElement != null && titleElement.text().isNotEmpty()) {
                        title = titleElement.text().trim()
                        titleFound = true
                        break
                    }
                }

                if (!titleFound) {
                    throw Exception("无法解析书籍标题 - 尝试的选择器: ${titleSelectors.joinToString(", ")} - URL: $requestUrl")
                }

                // 作者解析 - 基于实际HTML结构：<i><a class="color1" title="Find all the author's book" href="/author/...">
                // 用户反馈：需要在作者信息中添加作者链接标签
                val authorSelectors = listOf(
                    "i a.color1[title*='author']",
                    "i a.color1",
                    ".author", ".book-author", ".authors", ".writer",
                    "td:contains(作者) + td", "td:contains(Author) + td",
                    ".meta-author", "[data-author]", ".book-info .author",
                    ".bookProperty .property_value",
                )

                val authorList = mutableListOf<String>()
                val authorLinks = mutableListOf<String>()
                for (selector in authorSelectors) {
                    val authorElements = document.select(selector)
                    authorElements.forEach { element ->
                        val authorText = element.text().trim()
                        if (authorText.isNotEmpty() && !authorList.contains(authorText)) {
                            authorList.add(authorText)

                            // 如果是链接元素，保存链接信息
                            if (element.tagName() == "a") {
                                val href = element.attr("href")
                                if (href.isNotEmpty()) {
                                    val fullUrl = if (href.startsWith("/")) baseUrl + href else href
                                    authorLinks.add("[$authorText]($fullUrl)")
                                }
                            }
                        }
                    }
                    if (authorList.isNotEmpty()) break
                }

                if (authorList.isNotEmpty()) {
                    // 如果有作者链接，使用链接格式；否则使用纯文本
                    author = if (authorLinks.isNotEmpty()) {
                        authorLinks.joinToString(", ")
                    } else {
                        authorList.joinToString(", ")
                    }
                }

                // 描述解析 - 基于实际HTML结构：<div id="bookDescriptionBox">
                // 用户反馈：需要正确处理内容简介、作者简介、原文摘录三个部分的排版
                val descriptionSelectors = listOf(
                    "#bookDescriptionBox",
                    ".description", ".summary", ".book-description", ".book-summary", ".content", ".abstract", ".synopsis",
                    "#description", ".book-info .description",
                )

                for (selector in descriptionSelectors) {
                    val descElement = document.selectFirst(selector)
                    if (descElement != null && descElement.text().isNotEmpty()) {
                        // 处理描述的三个部分：内容简介、作者简介、原文摘录
                        val descriptionText = descElement.html()
                        val formattedDescription = StringBuilder()

                        // 分割描述内容，寻找三个主要部分
                        val sections = listOf(
                            "内容简介" to "内容简介\\s*·\\s*·\\s*·\\s*·\\s*·\\s*·",
                            "作者简介" to "作者简介\\s*·\\s*·\\s*·\\s*·\\s*·\\s*·",
                            "原文摘录" to "原文摘录\\s*·\\s*·\\s*·\\s*·\\s*·\\s*·",
                        )

                        var remainingText = descriptionText
                        var hasFormattedSections = false

                        for ((sectionName, pattern) in sections) {
                            val regex = Regex(pattern, RegexOption.IGNORE_CASE)
                            val match = regex.find(remainingText)
                            if (match != null) {
                                hasFormattedSections = true
                                val beforeSection = remainingText.substring(0, match.range.first).trim()
                                if (beforeSection.isNotEmpty() && formattedDescription.isNotEmpty()) {
                                    formattedDescription.append("\n\n")
                                }
                                if (beforeSection.isNotEmpty()) {
                                    formattedDescription.append(beforeSection.replace("<br>", "\n").replace(Regex("<[^>]*>"), ""))
                                }

                                formattedDescription.append("\n\n**$sectionName**\n")
                                remainingText = remainingText.substring(match.range.last + 1)

                                // 查找下一个部分的开始位置
                                val nextSectionIndex = sections.drop(sections.indexOfFirst { it.first == sectionName } + 1)
                                    .mapNotNull { (_, nextPattern) -> Regex(nextPattern, RegexOption.IGNORE_CASE).find(remainingText)?.range?.first }.minOrNull()

                                val sectionContent = if (nextSectionIndex != null) {
                                    remainingText.substring(0, nextSectionIndex)
                                } else {
                                    remainingText
                                }

                                val cleanContent = sectionContent.replace("<br>", "\n").replace(Regex("<[^>]*>"), "").trim()
                                if (cleanContent.isNotEmpty()) {
                                    formattedDescription.append(cleanContent)
                                }

                                if (nextSectionIndex != null) {
                                    remainingText = remainingText.substring(nextSectionIndex)
                                } else {
                                    remainingText = ""
                                    break
                                }
                            }
                        }

                        // 如果没有找到格式化的部分，使用原始文本
                        if (!hasFormattedSections) {
                            description = descElement.text().trim()
                        } else {
                            // 处理剩余文本
                            if (remainingText.isNotEmpty()) {
                                val cleanRemaining = remainingText.replace("<br>", "\n").replace(Regex("<[^>]*>"), "").trim()
                                if (cleanRemaining.isNotEmpty()) {
                                    formattedDescription.append("\n\n").append(cleanRemaining)
                                }
                            }
                            description = formattedDescription.toString().trim()
                        }
                        break
                    }
                }

                // 缩略图解析 - 基于实际HTML结构：<img class="image cover" src="...">
                // 用户反馈：需要确保获取到正确的封面图片，而不是替代图片
                // 只有当封面img加载完成，class="volume main show complete"时，才是正确的封面图片
                val thumbnailSelectors = listOf(
                    ".details-book-cover-container img.volume.main.show.complete",
                    ".details-book-cover-container img.image.cover",
                    "img.image.cover",
                    "img.cover",
                    ".book-cover img", ".cover img", ".thumbnail img",
                    ".book-image img", "img[alt*='cover']", ".main-image img",
                    ".book-info img", "img[src*='cover']",
                )

                for (selector in thumbnailSelectors) {
                    val imgElement = document.selectFirst(selector)
                    if (imgElement != null) {
                        // 检查是否是完全加载的封面图片
                        val classAttr = imgElement.attr("class")
                        val imgSrc = imgElement.attr("src") ?: imgElement.attr("data-src")

                        // 优先选择已完全加载的封面图片
                        if (selector.contains("volume.main.show.complete") && classAttr.contains("volume") && classAttr.contains("main") && classAttr.contains("show") && classAttr.contains("complete")) {
                            if (!imgSrc.isNullOrEmpty()) {
                                thumbnail_url = if (imgSrc.startsWith("/")) {
                                    baseUrl + imgSrc
                                } else {
                                    imgSrc
                                }
                                break
                            }
                        } else if (!imgSrc.isNullOrEmpty() && !imgSrc.contains("placeholder") && !imgSrc.contains("loading")) {
                            // 对于其他选择器，确保不是占位符图片
                            thumbnail_url = if (imgSrc.startsWith("/")) {
                                baseUrl + imgSrc
                            } else {
                                imgSrc
                            }
                            break
                        }
                    }
                }

                // 类型/分类解析 - 基于实际HTML结构：<div class="bookDetailsBox">中的Categories
                val genreSelectors = listOf(
                    ".bookDetailsBox .bookProperty.property_categories .property_value a",
                    ".bookProperty.property_categories .property_value a",
                    ".property_categories .property_value a",
                    ".genre", ".category", ".categories", ".tags",
                    ".book-genre", ".book-category", ".meta-genre",
                    "td:contains(类型) + td", "td:contains(Category) + td",
                    ".categories a", ".tags a", ".genre a",
                )

                val genreList = mutableListOf<String>()
                for (selector in genreSelectors) {
                    val genreElements = document.select(selector)
                    genreElements.forEach { element ->
                        val genreText = element.text().trim()
                        if (genreText.isNotEmpty() && !genreList.contains(genreText)) {
                            genreList.add(genreText)
                        }
                    }
                    if (genreList.isNotEmpty()) break
                }

                if (genreList.isNotEmpty()) {
                    genre = genreList.joinToString(", ")
                }

                // 从bookDetailsBox中提取更多信息
                val detailsBox = document.selectFirst(".bookDetailsBox")
                if (detailsBox != null) {
                    // 提取年份、出版商、语言等信息并添加到描述中
                    val additionalInfo = mutableListOf<String>()

                    detailsBox.select(".bookProperty").forEach { property ->
                        val label = property.selectFirst(".property_label")?.text()?.trim()
                        val value = property.selectFirst(".property_value")?.text()?.trim()

                        if (!label.isNullOrEmpty() && !value.isNullOrEmpty()) {
                            when (label.lowercase()) {
                                "year:", "年份:" -> additionalInfo.add("📅 年份: $value")
                                "publisher:", "出版社:" -> additionalInfo.add("🏢 出版社: $value")
                                "language:", "语言:" -> additionalInfo.add("🌐 语言: $value")
                                "pages:", "页数:" -> additionalInfo.add("📄 页数: $value")
                                "isbn 13:", "isbn:", "isbn-13:" -> additionalInfo.add("📚 ISBN: $value")
                                "file:", "文件:" -> {
                                    // 文件信息特殊处理，包含格式和大小
                                    val fileInfo = value.replace(",", " • ")
                                    additionalInfo.add("💾 文件: $fileInfo")
                                }
                                "categories:", "分类:" -> additionalInfo.add("🏷️ 分类: $value")
                                "extension:", "扩展名:" -> additionalInfo.add("📎 格式: $value")
                                "size:", "大小:" -> additionalInfo.add("📏 大小: $value")
                            }
                        }
                    }

                    // 如果没有找到文件信息，尝试从其他位置获取
                    if (!additionalInfo.any { it.contains("文件:") || it.contains("格式:") || it.contains("大小:") }) {
                        // 尝试从下载按钮获取文件信息
                        val downloadButton = document.selectFirst("a.addDownloadedBook")
                        if (downloadButton != null) {
                            val buttonText = downloadButton.text().trim()
                            if (buttonText.isNotEmpty() && !buttonText.equals("下载", ignoreCase = true)) {
                                additionalInfo.add("💾 文件: $buttonText")
                            }
                        }

                        // 尝试从文件格式选择器获取信息
                        val formatElements = document.select(".converterLink, .format-option")
                        if (formatElements.isNotEmpty()) {
                            val formats = formatElements.map { it.text().trim() }.filter { it.isNotEmpty() }
                            if (formats.isNotEmpty()) {
                                additionalInfo.add("📎 可用格式: ${formats.joinToString(", ")}")
                            }
                        }
                    }

                    if (additionalInfo.isNotEmpty()) {
                        val currentDesc = description ?: ""
                        description = if (currentDesc.isNotEmpty()) {
                            "$currentDesc\n\n📋 书籍信息:\n${additionalInfo.joinToString("\n")}"
                        } else {
                            "📋 书籍信息:\n${additionalInfo.joinToString("\n")}"
                        }
                    }
                }

                status = SManga.COMPLETED
            }
        } catch (e: Exception) {
            throw Exception("WebView详情解析失败: ${e.message}")
        }
    }

    // 移除parseApiDownloadLink方法，只使用WebView模式

    private fun parseWebDownloadLink(response: Response): List<Page> {
        return try {
            val requestUrl = response.request.url.toString()

            // 对于下载页面，使用WebView等待懒加载完成
            val responseBody = waitForLazyLoading(requestUrl, 2000)
            val document = Jsoup.parse(responseBody)

            // 首先尝试查找Read Online按钮（在线阅读）
            val readerSelectors = listOf(
                "a.reader-link",
                "a[href*='reader']",
                "a.dlButton.reader-link",
                "a:contains(Read Online)",
                "a:contains(在线阅读)",
                ".btn.reader-link",
                "[data-book_id] a[href*='read']",
            )

            for (selector in readerSelectors) {
                val readerElement = document.selectFirst(selector)
                if (readerElement != null) {
                    val readerUrl = readerElement.attr("href")
                    if (readerUrl.isNotEmpty()) {
                        // 处理相对URL
                        val fullReaderUrl = if (readerUrl.startsWith("/")) {
                            baseUrl + readerUrl
                        } else {
                            readerUrl
                        }
                        // 如果找到reader链接，使用专门的解析函数
                        return parseReaderPage(fullReaderUrl)
                    }
                }
            }

            // 如果没有找到在线阅读链接，尝试查找下载链接
            val downloadSelectors = listOf(
                "a.addDownloadedBook", // Z-Library主要下载按钮
                "a[href*='/dl/']", // Z-Library下载链接格式
                "a[href*='download']", ".download-btn", ".btn-download",
                "a:contains(下载)", "a:contains(Download)", "a:contains(PDF)",
                "a:contains(EPUB)", "a:contains(MOBI)", ".download-link",
                "[data-download]", ".download a", "#download-btn",
            )

            var downloadUrl: String? = null
            for (selector in downloadSelectors) {
                val downloadElement = document.selectFirst(selector)
                if (downloadElement != null) {
                    downloadUrl = downloadElement.attr("href")
                    if (!downloadUrl.isNullOrEmpty()) {
                        // 处理相对URL
                        if (downloadUrl.startsWith("/")) {
                            downloadUrl = baseUrl + downloadUrl
                        }
                        break
                    }
                }
            }

            // 如果没有找到直接下载链接，尝试查找表单提交
            if (downloadUrl.isNullOrEmpty()) {
                val formSelectors = listOf(
                    "form[action*='download']",
                    ".download-form",
                    "form:has(button:contains(下载))",
                    "form:has(button:contains(Download))",
                )

                for (selector in formSelectors) {
                    val formElement = document.selectFirst(selector)
                    if (formElement != null) {
                        val action = formElement.attr("action")
                        if (!action.isNullOrEmpty()) {
                            downloadUrl = if (action.startsWith("/")) {
                                baseUrl + action
                            } else {
                                action
                            }
                            break
                        }
                    }
                }
            }

            // 检查是否需要登录
            if (downloadUrl.isNullOrEmpty()) {
                val loginIndicators = listOf(
                    "a:contains(登录)",
                    "a:contains(Login)",
                    ".login-required",
                    ".auth-required",
                    "form[action*='login']",
                    ".signin",
                )

                val needsLogin = loginIndicators.any { selector ->
                    document.selectFirst(selector) != null
                }

                if (needsLogin) {
                    throw Exception("需要登录才能下载，请在WebView中登录后重试")
                }

                // 检查是否有访问限制
                val restrictionIndicators = listOf(
                    ":contains(访问限制)",
                    ":contains(Access denied)",
                    ":contains(Not available)",
                    ".error",
                    ".restriction",
                )

                val hasRestriction = restrictionIndicators.any { selector ->
                    document.select(selector).isNotEmpty()
                }

                if (hasRestriction) {
                    throw Exception("该书籍暂时不可下载，可能存在访问限制")
                }

                throw Exception("未找到下载链接，请检查书籍是否可用")
            }

            listOf(Page(0, "", downloadUrl))
        } catch (e: Exception) {
            if (e.message?.contains("需要登录") == true || e.message?.contains("访问限制") == true ||
                e.message?.contains("未找到下载链接") == true
            ) {
                throw e
            } else {
                throw Exception("WebView下载链接解析失败: ${e.message}")
            }
        }
    }

    // 配置界面
    override fun setupPreferenceScreen(screen: PreferenceScreen) {
        // 域名选择
        ListPreference(screen.context).apply {
            key = PREF_DOMAIN_KEY
            title = "选择域名"
            summary = "选择Z-Library访问域名，如果当前域名无法访问请尝试其他域名"
            entries = domainNames
            entryValues = domains
            setDefaultValue(domains[0])

            setOnPreferenceChangeListener { _, newValue ->
                val index = domains.indexOf(newValue)
                summary = "当前域名: ${domainNames[index]} - 如果无法访问请尝试其他域名"
                true
            }
        }.also(screen::addPreference)

        // 访问模式选择
        SwitchPreferenceCompat(screen.context).apply {
            key = PREF_API_MODE_KEY
            title = "使用API模式"
            summary = "API模式速度更快但可能不稳定，WebView模式更稳定但速度较慢"
            setDefaultValue(false)

            setOnPreferenceChangeListener { _, newValue ->
                summary = if (newValue as Boolean) {
                    "当前: API模式 - 速度快但可能不稳定"
                } else {
                    "当前: WebView模式 - 稳定但速度较慢"
                }
                true
            }
        }.also(screen::addPreference)

        // 添加帮助信息 - 使用EditTextPreference作为只读信息显示
        androidx.preference.EditTextPreference(screen.context).apply {
            title = "使用说明"
            summary = "• 如果遇到访问问题，请先尝试切换域名\n• API模式失效时请切换到WebView模式\n• 部分内容可能需要登录才能访问"
            setDefaultValue("")
            key = "help_info"
        }.also(screen::addPreference)
    }

    // WebView懒加载等待机制 - 增强封面图片加载检测
    private fun waitForLazyLoading(url: String, waitTimeMs: Long = 3000): String {
        val context = Injekt.get<Application>()
        val handler = Handler(Looper.getMainLooper())
        val latch = CountDownLatch(1)
        var webView: WebView? = null
        var finalHtml = ""
        var hasError = false
        var errorMessage = ""
        var loadingAttempts = 0
        val maxAttempts = 3

        handler.post {
            val webview = WebView(context).also { webView = it }

            with(webview.settings) {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                userAgentString = headers["User-Agent"]
                // 启用图片加载
                loadsImagesAutomatically = true
                blockNetworkImage = false
            }

            webview.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    loadingAttempts++

                    // 检查懒加载图片是否已完全加载
                    val checkImagesScript = """
                        (function() {
                            var images = document.querySelectorAll('img[data-src], img.image.cover, z-cover img');
                            var loadedCount = 0;
                            var totalCount = images.length;
                            
                            for (var i = 0; i < images.length; i++) {
                                var img = images[i];
                                var dataSrc = img.getAttribute('data-src');
                                var src = img.getAttribute('src');
                                
                                // 检查图片是否已从data-src加载到src，或者src已包含真实图片URL
                                if (src && src !== '' && !src.startsWith('data:') && 
                                    (src.includes('cdn-zlib') || src.includes('zlibcdn') || src.includes('covers') || src.includes('.jpg'))) {
                                    loadedCount++;
                                } else if (dataSrc && dataSrc !== '' && 
                                    (dataSrc.includes('cdn-zlib') || dataSrc.includes('zlibcdn') || dataSrc.includes('covers') || dataSrc.includes('.jpg'))) {
                                    // 如果data-src有效但src还没更新，触发懒加载
                                    img.src = dataSrc;
                                    loadedCount++;
                                }
                            }
                            
                            return {
                                loaded: loadedCount,
                                total: totalCount,
                                ready: totalCount === 0 || loadedCount >= Math.max(1, Math.floor(totalCount * 0.8))
                            };
                        })();
                    """

                    view?.evaluateJavascript(checkImagesScript) { result ->
                        try {
                            val isReady = result?.contains("\"ready\":true") == true

                            if (isReady || loadingAttempts >= maxAttempts) {
                                // 图片加载完成或达到最大尝试次数，获取最终HTML
                                handler.postDelayed({
                                    view?.evaluateJavascript("document.documentElement.outerHTML") { html ->
                                        finalHtml = html?.removeSurrounding("\"")?.replace("\\\"", "\"")?.replace("\\n", "\n") ?: ""
                                        latch.countDown()
                                    }
                                }, if (isReady) 500 else waitTimeMs,)
                            } else {
                                // 继续等待，但不超过总等待时间
                                handler.postDelayed({
                                    if (latch.count > 0) {
                                        view?.evaluateJavascript("document.documentElement.outerHTML") { html ->
                                            finalHtml = html?.removeSurrounding("\"")?.replace("\\\"", "\"")?.replace("\\n", "\n") ?: ""
                                            latch.countDown()
                                        }
                                    }
                                }, waitTimeMs,)
                            }
                        } catch (e: Exception) {
                            hasError = true
                            errorMessage = "图片加载检测失败: ${e.message}"
                            latch.countDown()
                        }
                    }
                }

                override fun onReceivedError(view: WebView?, errorCode: Int, description: String?, failingUrl: String?) {
                    super.onReceivedError(view, errorCode, description, failingUrl)
                    hasError = true
                    errorMessage = "WebView加载错误 (代码: $errorCode): $description"
                    latch.countDown()
                }

                override fun onReceivedHttpError(view: WebView?, request: WebResourceRequest?, errorResponse: WebResourceResponse?) {
                    super.onReceivedHttpError(view, request, errorResponse)
                    if (request?.url?.toString() == url) {
                        hasError = true
                        errorMessage = "HTTP错误 (代码: ${errorResponse?.statusCode}): ${errorResponse?.reasonPhrase}"
                        latch.countDown()
                    }
                }
            }

            try {
                webview.loadUrl(url)
            } catch (e: Exception) {
                hasError = true
                errorMessage = "WebView启动失败: ${e.message}"
                latch.countDown()
            }
        }

        try {
            // 等待最多15秒，给图片更多加载时间
            val timeoutReached = !latch.await(15, TimeUnit.SECONDS)

            if (timeoutReached) {
                errorMessage = "封面图片加载超时 (超过15秒) - 当前域名: ${baseUrl.toHttpUrl().host}"
                hasError = true
            }

            if (hasError) {
                // 如果WebView加载失败，抛出具体错误而不是回退到HTTP请求
                throw Exception(errorMessage.ifEmpty { "封面图片获取失败 - 当前域名: ${baseUrl.toHttpUrl().host}" })
            }
        } catch (e: Exception) {
            // 只有在非WebView错误时才回退到普通HTTP请求
            if (!hasError) {
                val request = GET(url, headers)
                val response = client.newCall(request).execute()
                finalHtml = getResponseBodyWithCorrectEncoding(response)
            } else {
                throw e
            }
        } finally {
            // 清理WebView
            handler.post {
                webView?.destroy()
            }
        }

        return finalHtml
    }

    // 解析搜索结果中的书籍项目
    private fun parseSearchBookItem(item: org.jsoup.nodes.Element): SManga? {
        return try {
            val manga = SManga.create()

            // 获取书籍URL
            val bookUrl = extractBookUrl(item) ?: return null
            manga.url = bookUrl

            // 获取书籍标题
            manga.title = extractBookTitle(item)

            // 获取作者信息
            val bookcard = item.selectFirst("z-bookcard")
            manga.author = bookcard?.attr("author")?.takeIf { it.isNotBlank() } ?: extractAuthor(item)

            // 获取封面图片
            manga.thumbnail_url = extractThumbnailUrl(item)

            // 设置其他属性
            manga.status = SManga.UNKNOWN
            manga.initialized = false

            manga
        } catch (e: Exception) {
            null
        }
    }

    // 解析热门书籍项目 - 与搜索结果类似但针对主页优化
    private fun parsePopularBookItem(item: org.jsoup.nodes.Element): SManga? {
        return try {
            val manga = SManga.create()

            // 获取书籍URL
            val bookUrl = extractBookUrl(item) ?: return null
            manga.url = bookUrl

            // 获取书籍标题
            manga.title = extractBookTitle(item)

            // 获取作者信息
            val zCover = item.selectFirst("z-cover")
            manga.author = zCover?.attr("author")?.takeIf { it.isNotBlank() } ?: extractAuthor(item)

            // 获取封面图片
            manga.thumbnail_url = extractThumbnailUrl(item)

            // 设置其他属性
            manga.status = SManga.COMPLETED
            manga.initialized = false

            manga
        } catch (e: Exception) {
            null
        }
    }

    // 公共工具方法
    private fun isValidImageUrl(url: String?): Boolean {
        if (url.isNullOrEmpty()) return false
        // 排除明显的占位符和无效URL
        if (url.startsWith("data:image/svg") || url.contains("placeholder") || url.contains("loading") || url.length < 10) return false
        // 放宽验证条件，接受更多类型的图片URL
        return url.startsWith("http") || url.startsWith("//") || url.startsWith("/")
    }

    private fun normalizeUrl(url: String): String {
        return when {
            url.startsWith("//") -> "https:$url"
            url.startsWith("/") -> "$baseUrl$url"
            else -> url
        }
    }

    private fun extractThumbnailUrl(element: org.jsoup.nodes.Element): String? {
        val imgSelectors = listOf(
            "img[src]",
            ".book-cover img",
            ".cover img",
            "z-cover img",
            "img",
        )

        for (selector in imgSelectors) {
            val imgElement = element.selectFirst(selector)
            if (imgElement != null) {
                val imgUrl = imgElement.attr("src").ifEmpty { imgElement.attr("data-src") }
                if (isValidImageUrl(imgUrl)) {
                    return normalizeUrl(imgUrl)
                }
            }
        }
        return null
    }

    private fun extractBookTitle(element: org.jsoup.nodes.Element): String {
        val titleSelectors = listOf(
            "h3 a",
            ".book-title a",
            "a[title]",
            "h3",
            ".title",
        )

        for (selector in titleSelectors) {
            val titleElement = element.selectFirst(selector)
            if (titleElement != null) {
                val title = titleElement.attr("title").ifEmpty { titleElement.text() }
                if (title.isNotBlank()) {
                    return title.trim()
                }
            }
        }
        return "未知标题"
    }

    private fun extractBookUrl(element: org.jsoup.nodes.Element): String? {
        val linkSelectors = listOf(
            "h3 a[href]",
            ".book-title a[href]",
            "a[href]",
        )

        for (selector in linkSelectors) {
            val linkElement = element.selectFirst(selector)
            if (linkElement != null) {
                val href = linkElement.attr("href")
                if (href.isNotBlank()) {
                    return normalizeUrl(href)
                }
            }
        }
        return null
    }

    private fun extractAuthor(element: org.jsoup.nodes.Element): String {
        val authorSelectors = listOf(
            ".author",
            ".book-author",
            "div:contains(作者)",
            "span:contains(作者)",
        )

        for (selector in authorSelectors) {
            val authorElement = element.selectFirst(selector)
            if (authorElement != null) {
                val author = authorElement.text().trim()
                if (author.isNotBlank() && !author.contains("作者")) {
                    return author
                }
            }
        }
        return "未知作者"
    }

    companion object {
        private const val PREF_DOMAIN_KEY = "domain_preference"
        private const val PREF_API_MODE_KEY = "api_mode_preference"
    }
}

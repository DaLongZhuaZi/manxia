package eu.kanade.tachiyomi.extension.zh.mtldss

import android.util.Base64
import androidx.preference.PreferenceScreen
import eu.kanade.tachiyomi.lib.randomua.addRandomUAPreferenceToScreen
import eu.kanade.tachiyomi.lib.randomua.getPrefCustomUA
import eu.kanade.tachiyomi.lib.randomua.getPrefUAType
import eu.kanade.tachiyomi.lib.randomua.setRandomUserAgent
import eu.kanade.tachiyomi.network.GET
import eu.kanade.tachiyomi.network.asObservableSuccess
import eu.kanade.tachiyomi.network.interceptor.rateLimitHost
import eu.kanade.tachiyomi.source.ConfigurableSource
import eu.kanade.tachiyomi.source.model.Filter
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.online.ParsedHttpSource
import eu.kanade.tachiyomi.util.asJsoup
import keiyoushi.utils.getPreferences
import keiyoushi.utils.tryParse
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import org.jsoup.select.Elements
import rx.Observable
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Locale

class Mtldss : ParsedHttpSource(), ConfigurableSource {

    override val lang: String = "zh"
    override val name: String = "每天来点色色"
    override val supportsLatest: Boolean = true

    private val preferences = getPreferences { preferenceMigration() }

    override val baseUrl: String = "https://mtldss.top"

    // 处理URL请求
    override val client: OkHttpClient = network.cloudflareClient
        .newBuilder()
        // Add rate limit to fix manga thumbnail load failure
        .rateLimitHost(
            baseUrl.toHttpUrl(),
            preferences.getString(MAINSITE_RATELIMIT_PREF, MAINSITE_RATELIMIT_PREF_DEFAULT)!!.toInt(),
            preferences.getString(MAINSITE_RATELIMIT_PERIOD, MAINSITE_RATELIMIT_PERIOD_DEFAULT)!!.toLong(),
        )
        .setRandomUserAgent(preferences.getPrefUAType(), preferences.getPrefCustomUA())
        .addInterceptor(ScrambledImageInterceptor)
        .addInterceptor(LoginInterceptor(preferences))
        .build()

    // 添加额外的header增加规避Cloudflare可能性
    override fun headersBuilder() = super.headersBuilder()
        .set("Referer", "$baseUrl/")

    // 全新出炉(热门) - 改为在“日韩写真”专题页识别（无弹窗）
    override fun popularMangaRequest(page: Int): Request {
        val topic = "/index.php/topics/japanese-korean-photobook/"
        return if (page == 1) {
            GET("$baseUrl$topic", headers)
        } else {
            GET("$baseUrl$topic/page/$page/", headers)
        }
    }

    override fun popularMangaNextPageSelector(): String = "div.next-page.ajax-next a"
    override fun popularMangaSelector(): String {
        // 兼容卡片样式与列表样式，两者结构一致，仅外层 class 不同
        return ".posts-item.card.ajax-item, .posts-item.list.ajax-item"
    }

    // 搜索结果页面使用不同的选择器
    override fun searchMangaSelector(): String {
        return ".posts-item.card.ajax-item, .posts-item.list.ajax-item"
    }

    // 根据URL类型选择正确的选择器
    private fun getSelectorForUrl(url: String): String {
        return when {
            url.contains("/topics/") || url.contains("/models/") -> popularMangaSelector()
            url.contains("?s=") -> searchMangaSelector()
            else -> popularMangaSelector()
        }
    }

    private fun List<SManga>.filterGenre(): List<SManga> {
        val removedGenres = preferences.getString(BLOCK_PREF, "")!!.substringBefore("//").trim()
        if (removedGenres.isEmpty()) return this
        val removedList = removedGenres.lowercase().split(' ')
        return this.filterNot { manga ->
            manga.genre.orEmpty().lowercase().split(", ").any { removedList.contains(it) }
        }
    }

    override fun popularMangaFromElement(element: Element): SManga = SManga.create().apply {
        // 从posts-item元素中提取信息
        val linkElement = element.selectFirst("div.item-thumbnail a") ?: element.selectFirst("h2.item-heading a")
        val titleElement = element.selectFirst("h2.item-heading a")
        val imgElement = element.selectFirst("div.item-thumbnail img")

        title = titleElement?.text() ?: "未知标题"

        // 修复URL设置逻辑，确保正确处理相对和绝对URL
        val href = linkElement?.attr("href") ?: ""
        url = when {
            href.startsWith("http") -> href.removePrefix(baseUrl)
            href.startsWith("/") -> href
            else -> "/$href"
        }

        // 提取缩略图URL - 改进提取逻辑
        val imgSrc = imgElement?.let { img ->
            when {
                img.hasAttr("data-original") -> img.attr("data-original")
                img.hasAttr("data-src") -> img.attr("data-src")
                img.hasAttr("src") -> img.attr("src")
                img.hasAttr("data-cfsrc") -> img.attr("data-cfsrc")
                else -> ""
            }
        } ?: ""

        thumbnail_url = if (imgSrc.isNotEmpty()) {
            // 清理URL参数并确保是完整的URL
            val cleanUrl = imgSrc.substringBeforeLast('?')
            // 修复URL拼接逻辑，避免重复拼接baseUrl
            when {
                cleanUrl.startsWith("http") -> cleanUrl
                cleanUrl.startsWith("/") -> "$baseUrl$cleanUrl"
                else -> "$baseUrl/$cleanUrl"
            }
        } else {
            ""
        }

        // 提取作者信息（从meta-author部分）
        val authorElement = element.selectFirst("item.meta-author a")
        author = authorElement?.text() ?: ""

        // 提取标签信息 - 从item-tags区域获取所有标签
        val tagElements = element.select("div.item-tags a")
        val tags = mutableListOf<String>()

        tagElements.forEach { tagElement ->
            val tagText = tagElement.text().trim()
            // 处理不同类型的标签
            when {
                tagText.startsWith("#") -> tags.add(tagText.removePrefix("#").trim())
                tagElement.hasClass("but") -> {
                    // 处理分类标签（写真、Cosplay等）和专题标签
                    val cleanText = tagText.replace(Regex("^[\\s\\S]*?\\s"), "").trim()
                    if (cleanText.isNotEmpty()) tags.add(cleanText)
                }
                else -> tags.add(tagText)
            }
        }

        genre = tags.distinct().joinToString(", ")
    }

    override fun popularMangaParse(response: Response): MangasPage {
        val document = sanitizeAndInject(response.asJsoup())
        val elements = document.select(popularMangaSelector())
        val mangas = elements.map { popularMangaFromElement(it) }
        val hasNextPage = hasNext(document)
        return MangasPage(mangas.filterGenre(), hasNextPage)
    }

    // 最近更新 - 改为使用“未流出”专题页（无弹窗），分页使用 /page/{page}/
    override fun latestUpdatesRequest(page: Int): Request {
        val topic = "/index.php/topics/unleashed/"
        return if (page == 1) {
            GET("$baseUrl$topic", headers)
        } else {
            GET("$baseUrl$topic/page/$page/", headers)
        }
    }

    override fun latestUpdatesNextPageSelector(): String = "link[rel=next], div.next-page.ajax-next a"
    override fun latestUpdatesSelector(): String = popularMangaSelector()
    override fun latestUpdatesFromElement(element: Element): SManga = popularMangaFromElement(element)

    override fun latestUpdatesParse(response: Response): MangasPage {
        val document = sanitizeAndInject(response.asJsoup())
        val elements = document.select(latestUpdatesSelector())
        val mangas = elements.map { latestUpdatesFromElement(it) }
        val hasNextPage = hasNext(document)
        return MangasPage(mangas.filterGenre(), hasNextPage)
    }

    // For MtldssUrlActivity
    private fun searchMangaByIdRequest(id: String) = GET("$baseUrl/album/$id", headers)

    private fun searchMangaByIdParse(response: Response, id: String): MangasPage {
        val sManga = mangaDetailsParse(response)
        sManga.url = "/album/$id/"
        return MangasPage(listOf(sManga), false)
    }

    override fun fetchSearchManga(page: Int, query: String, filters: FilterList): Observable<MangasPage> {
        return if (query.startsWith(PREFIX_ID_SEARCH_NO_COLON, true) || query.toIntOrNull() != null) {
            val id = query.removePrefix(PREFIX_ID_SEARCH_NO_COLON).removePrefix(":")
            client.newCall(searchMangaByIdRequest(id))
                .asObservableSuccess()
                .map { response -> searchMangaByIdParse(response, id) }
        } else {
            super.fetchSearchManga(page, query, filters)
        }
    }

    // 查询信息
    override fun searchMangaRequest(page: Int, query: String, filters: FilterList): Request {
        var params = filters.filterIsInstance<UriPartFilter>().joinToString("") { it.toUriPart() }

        val url = if (query.isNotEmpty()) {
            // 直接使用网址格式进行搜索: https://mtldss.top/?s=关键词&type=post
            // 完整URL编码以支持中文及特殊字符
            val encodedQuery = URLEncoder.encode(query, "UTF-8")
            if (page > 1) {
                "$baseUrl/index.php/page/$page/?s=$encodedQuery&type=post"
            } else {
                "$baseUrl/?s=$encodedQuery&type=post"
            }
        } else {
            // 没有搜索词时，使用过滤器参数
            params = if (params == "") "/albums?" else params
            if (page > 1) {
                "$baseUrl/index.php$params&page=$page"
            } else {
                "$baseUrl$params"
            }
        }
        return GET(url, headers)
    }

    override fun searchMangaNextPageSelector(): String = popularMangaNextPageSelector()
    override fun searchMangaFromElement(element: Element): SManga = popularMangaFromElement(element)

    override fun searchMangaParse(response: Response): MangasPage {
        val document = sanitizeAndInject(response.asJsoup())
        val selector = getSelectorForUrl(response.request.url.toString())
        val elements = document.select(selector)
        val mangas = elements.map { popularMangaFromElement(it) }
        val hasNextPage = hasNext(document)
        return MangasPage(mangas.filterGenre(), hasNextPage)
    }

    // 统一“加载更多”与“无更多内容”检测逻辑
    private fun noMoreContentSelector(): String =
        "div.text-center.mb20.padding-h10.muted-2-color.no-more.separator"

    private fun hasNext(document: Document): Boolean {
        // 如果页面已出现“没有更多内容了”，则停止分页
        if (document.select(noMoreContentSelector()).isNotEmpty()) return false
        // 优先识别标准分页标记
        if (document.selectFirst("link[rel=next]") != null) return true
        // 兼容站点使用的 Ajax 加载更多按钮
        if (document.select("div.next-page.ajax-next a").isNotEmpty()) return true
        return false
    }

    // 漫画详情
    private fun sanitizeAndInject(document: Document): Document {
        // 先解析并注入脚本生成的内容，再移除弹窗与遮罩，避免误删脚本
        // 处理通过 base64 注入的 HTML（该站常见，脚本位置和写法可能变化）
        // 兼容：base64DecodeUtf8("...") / base64DecodeUtf8('...') / atob("...") / atob('...')
        // 兼容：多段拼接 'abc' + 'def'
        val scripts = document.select("script")
        val callPatterns = listOf(
            Regex("""base64DecodeUtf8\s*\(\s*(.*?)\s*\)"""),
            Regex("""atob\s*\(\s*(.*?)\s*\)"""),
        )
        // 支持 Base64 与 Base64URL（包含 -/_），并允许多段拼接
        val quotedPartRegex = Regex("""['\"]([-_A-Za-z0-9+/=]+)['\"]""")
        for (script in scripts) {
            val jsCode = script.html()
            for (pattern in callPatterns) {
                val matches = pattern.findAll(jsCode)
                for (match in matches) {
                    val inside = match.groupValues.getOrNull(1) ?: continue
                    val parts = quotedPartRegex.findAll(inside).map { it.groupValues[1] }.toList()
                    if (parts.isEmpty()) continue
                    val base64Concat = parts.joinToString("")
                    try {
                        // 先尝试标准 Base64 解码
                        val decoded = Base64.decode(base64Concat, Base64.DEFAULT)
                        document.body().append(String(decoded, Charsets.UTF_8))
                    } catch (_: IllegalArgumentException) {
                        // 回退：尝试 Base64URL 转换为标准 Base64 后再解码
                        val std = base64Concat.replace('-', '+').replace('_', '/')
                        val padded = std + "=".repeat((4 - std.length % 4) % 4)
                        try {
                            val decoded = Base64.decode(padded, Base64.DEFAULT)
                            document.body().append(String(decoded, Charsets.UTF_8))
                        } catch (_: IllegalArgumentException) {
                            // 忽略无法解析的片段
                        }
                    }
                }
            }
        }

        // 再移除特定弹窗与遮罩（避免使用过于宽泛的选择器）
        document.select(
            listOf(
                "#modal-system-notice", // 系统公告弹窗
                ".modal-backdrop", // 关闭方式②：点击弹窗外区域的遮罩
                ".mfp-bg",
                ".mfp-wrap",
                "#mask",
                ".mask",
                ".overlay",
            ).joinToString(", "),
        ).remove()
        document.select("body.modal-open").removeClass("modal-open")

        return document
    }

    private fun mangaDetailsResolve(response: Response): Document {
        val document = response.asJsoup()
        return sanitizeAndInject(document)
    }

    override fun mangaDetailsParse(response: Response): SManga {
        val document = mangaDetailsResolve(response)
        return mangaDetailsParse(document)
    }

    override fun mangaDetailsParse(document: Document): SManga = SManga.create().apply {
        title = document.selectFirst("h1")!!.text()
        // 改进缩略图URL提取逻辑，保持与popularMangaFromElement一致
        val thumbImg = document.selectFirst(".thumb-overlay > img")
        thumbnail_url = if (thumbImg != null) {
            val imgUrl = thumbImg.extractThumbnailUrl()
            if (imgUrl.isNotEmpty()) {
                val cleanUrl = imgUrl.substringBeforeLast('.')
                val finalUrl = "${cleanUrl}_3x4.jpg"
                // 修复URL拼接逻辑，避免重复拼接baseUrl
                when {
                    finalUrl.startsWith("http") -> finalUrl
                    finalUrl.startsWith("/") -> "$baseUrl$finalUrl"
                    else -> "$baseUrl/$finalUrl"
                }
            } else {
                ""
            }
        } else {
            ""
        }
        author = selectAuthor(document)
        genre = selectDetailsStatusAndGenre(document, 0).trim().split(" ").joinToString(", ")

        // 默认设置为已完结状态 (2 = 已完结)
        status = SManga.COMPLETED
        description = document.selectFirst("#intro-block .p-t-5.p-b-5")?.text()?.substringAfter("敘述：")?.trim() ?: ""
    }

    private fun Element.extractThumbnailUrl(): String {
        return when {
            hasAttr("data-original") -> attr("data-original")
            hasAttr("src") -> attr("src")
            hasAttr("data-cfsrc") -> attr("data-cfsrc")
            else -> ""
        }
    }

    // 查询作者信息 - 从URL中提取作者名
    private fun selectAuthor(document: Document): String {
        // 首先尝试从URL中提取作者信息
        val url = document.location()
        if (url.isNotEmpty()) {
            // 从URL路径中提取作者名，例如：/2025/10/09/byoru-eclipse... -> "byoru"
            val pathSegments = url.split("/").filter { it.isNotEmpty() }
            if (pathSegments.size >= 4) {
                // 跳过年月日部分，获取实际的标题部分
                val titleSegment = pathSegments[3] // 获取标题部分 (跳过年/月/日)
                val authorMatch = titleSegment.split("-").firstOrNull()
                if (!authorMatch.isNullOrEmpty() && !authorMatch.matches(Regex("\\d+"))) {
                    // 首字母大写，确保不是数字
                    return authorMatch.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
                }
            }
        }

        // 备用方案：尝试从页面标题中提取
        val title = document.selectFirst("h1")?.text() ?: ""
        if (title.isNotEmpty()) {
            // 尝试从标题中提取作者名（通常在开头）
            val titleParts = title.split("【", "〖", "[", "（", "(")
            if (titleParts.isNotEmpty()) {
                val firstPart = titleParts[0].trim()
                val words = firstPart.split(" ", "　")
                if (words.isNotEmpty()) {
                    return words[0]
                }
            }
        }

        // 最后备用方案：尝试从原有的tag-block中获取（安全访问）
        val tagBlocks = document.select("div.panel-body div.tag-block")
        if (tagBlocks.size > 3) {
            val element = tagBlocks[3]
            val authors = element.select(".btn-primary").joinToString { it.text() }
            if (authors.isNotEmpty()) {
                return authors
            }
        }

        return "未知作者"
    }

    // 查询漫画状态和类别信息
    private fun selectDetailsStatusAndGenre(document: Document, index: Int): String {
        var status = "0"
        var genre = ""
        if (document.select("span[itemprop=genre] a").size == 0) {
            return if (index == 1) {
                status
            } else {
                genre
            }
        }
        val elements: Elements = document.select("span[itemprop=genre]").first()!!.select("a")
        for (value in elements) {
            when (val vote: String = value.select("a").text()) {
                "連載中" -> {
                    status = "1"
                }
                "完結" -> {
                    status = "2"
                }
                else -> {
                    genre = "$genre$vote "
                }
            }
        }
        return if (index == 1) {
            status
        } else {
            genre
        }
    }

    // 漫画章节信息
    override fun chapterListSelector(): String = "div[id=episode-block] a[href^=/photo/]"

    private val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.ENGLISH)

    override fun chapterFromElement(element: Element): SChapter = SChapter.create().apply {
        val href = element.select("a").attr("href")
        // 修复URL拼接逻辑，避免重复拼接baseUrl
        url = when {
            href.startsWith("http") -> href
            href.startsWith("/") -> "$baseUrl$href"
            else -> "$baseUrl/$href"
        }
        name = element.select("a li h3").first()!!.ownText()
        date_upload = dateFormat.tryParse(element.select("a li span.hidden-xs").text().trim())
    }

    override fun chapterListParse(response: Response): List<SChapter> {
        val document = mangaDetailsResolve(response)

        // 由于mtldss网站没有目录机制，直接创建单个章节
        val singleChapter = SChapter.create().apply {
            name = "图片内容"
            // 修复URL处理，确保使用正确的相对URL
            val fullUrl = response.request.url.toString()
            url = when {
                fullUrl.startsWith(baseUrl) -> fullUrl.removePrefix(baseUrl)
                fullUrl.startsWith("http") -> {
                    // 如果是其他域名的完整URL，提取路径部分
                    try {
                        val uri = java.net.URI(fullUrl)
                        uri.path
                    } catch (e: Exception) {
                        fullUrl
                    }
                }
                else -> fullUrl
            }

            // 从URL中提取日期信息
            date_upload = extractDateFromUrl(response.request.url.toString()) ?: run {
                // 备用方案：从HTML中获取发布日期
                document.select("div.px12-sm.muted-2-color.text-ellipsis span[data-original-title]").attr("data-original-title").let { dateStr ->
                    if (dateStr.isNotEmpty()) {
                        // 解析类似 "2025年10月10日 11:51发布" 的日期格式
                        val datePattern = Regex("""(\d{4})年(\d{1,2})月(\d{1,2})日""")
                        val matchResult = datePattern.find(dateStr)
                        if (matchResult != null) {
                            val (year, month, day) = matchResult.destructured
                            val formattedDate = "$year-${month.padStart(2, '0')}-${day.padStart(2, '0')}"
                            dateFormat.tryParse(formattedDate)
                        } else {
                            // 如果新格式解析失败，尝试其他选择器
                            document.select("[itemprop=datePublished]").attr("content").let { fallbackDateStr ->
                                if (fallbackDateStr.isNotEmpty()) {
                                    dateFormat.tryParse(fallbackDateStr)
                                } else {
                                    document.select(".post-date, .entry-date, time").attr("datetime").let { altDateStr ->
                                        if (altDateStr.isNotEmpty()) dateFormat.tryParse(altDateStr) else 0L
                                    }
                                }
                            }
                        }
                    } else {
                        // 如果没有找到新格式的日期，尝试其他选择器
                        document.select("[itemprop=datePublished]").attr("content").let { fallbackDateStr ->
                            if (fallbackDateStr.isNotEmpty()) {
                                dateFormat.tryParse(fallbackDateStr)
                            } else {
                                document.select(".post-date, .entry-date, time").attr("datetime").let { altDateStr ->
                                    if (altDateStr.isNotEmpty()) dateFormat.tryParse(altDateStr) else 0L
                                }
                            }
                        }
                    }
                }
            }
        }
        return listOf(singleChapter)
    }

    // 从URL中提取日期信息
    private fun extractDateFromUrl(url: String): Long? {
        // 从URL路径中提取日期，例如：/2025/10/09/byoru-eclipse... -> "2025-10-09"
        val pathSegments = url.split("/")
        if (pathSegments.size >= 4) {
            try {
                val year = pathSegments[pathSegments.size - 4]
                val month = pathSegments[pathSegments.size - 3]
                val day = pathSegments[pathSegments.size - 2]

                // 验证是否为有效的日期格式
                if (year.length == 4 && month.length <= 2 && day.length <= 2) {
                    val formattedDate = "$year-${month.padStart(2, '0')}-${day.padStart(2, '0')}"
                    return dateFormat.tryParse(formattedDate)
                }
            } catch (e: Exception) {
                // 如果解析失败，返回null使用备用方案
            }
        }
        return null
    }

    // 漫画图片信息
    override fun pageListParse(document: Document): List<Page> {
        val pages = mutableListOf<Page>()

        // 从.article-content中提取图片，过滤视频内容
        val articleContent = document.select("div.article-content")

        if (articleContent.isEmpty()) {
            // 如果没有找到article-content，返回空列表
            return emptyList()
        }

        // 选择所有图片元素，排除视频播放器中的图片
        val imageElements = articleContent.select("img").filter { img ->
            // 过滤掉视频播放器相关的图片
            val parent = img.parent()
            val isInVideoPlayer = parent?.hasClass("dplayer-video-wrap") == true ||
                parent?.hasClass("new-dplayer") == true ||
                img.hasClass("dplayer-video") == true
            !isInVideoPlayer
        }

        imageElements.forEachIndexed { index, img ->
            // 优先使用data-src属性（懒加载），fallback到src属性
            val imageUrl = img.attr("data-src").takeIf { it.isNotEmpty() }
                ?: img.attr("src").takeIf { it.isNotEmpty() }
                ?: ""

            if (imageUrl.isNotEmpty() && !imageUrl.contains("blank.jpg")) {
                // 移除URL中的查询参数
                val cleanUrl = imageUrl.split("?")[0]
                pages.add(Page(index, "", cleanUrl))
            }
        }

        return pages
    }

    override fun imageUrlParse(document: Document): String = throw UnsupportedOperationException()

    // Filters
    // 按照类别信息进行检索

    override fun getFilterList() = FilterList(
        TopicFilter(),
        SubTopicFilter(),
        ModelFilter(),
    )

    private class TopicFilter : UriPartFilter(
        "专题",
        arrayOf(
            Pair("全部", ""),
            Pair("未流出", "/index.php/topics/unleashed/"),
            Pair("Cosplay", "/index.php/topics/cosplay/"),
            Pair("日韩写真", "/index.php/topics/japanese-korean-photobook/"),
            Pair("秀人", "/index.php/topics/xiuren-series/"),
        ),
    )

    private class SubTopicFilter : UriPartFilter(
        "子专题",
        arrayOf(
            Pair("全部", ""),
            // 动漫游戏相关
            Pair("碧蓝航线", "/index.php/topics/azurlane/"),
            Pair("2.5次元的诱惑", "/index.php/topics/2-5-dimensional-seduction/"),
            Pair("Re:从零开始的异世界生活", "/index.php/topics/re0/"),
            Pair("VOCALOID", "/index.php/topics/vocaloid/"),
            Pair("交错战线", "/index.php/topics/cross-core/"),
            Pair("刀剑神域", "/index.php/topics/sword-art-online/"),
            Pair("剑星", "/index.php/topics/stellar-blade/"),
            Pair("化物语", "/index.php/topics/bakemonogatari/"),
            Pair("原创角色", "/index.php/topics/original-character/"),
            Pair("原神", "/index.php/topics/genshin-impact/"),
            Pair("命运 Fate", "/index.php/topics/fate/"),
            Pair("胜利女神：妮姬 NIKKE", "/index.php/topics/nikke/"),
            Pair("尼尔", "/index.php/topics/nier/"),
            Pair("崩坏：星穹铁道", "/index.php/topics/hsr/"),
            Pair("怪物猎人", "/index.php/topics/monster-hunter/"),
            Pair("更衣人偶坠入爱河", "/index.php/topics/my-dress-up-darling/"),
            Pair("死或生", "/index.php/topics/dead-or-alive/"),
            Pair("死神", "/index.php/topics/bleach/"),
            Pair("永劫无间", "/index.php/topics/nakara_bladepoint/"),
            Pair("漫威", "/index.php/topics/marvel/"),
            Pair("英雄联盟", "/index.php/topics/lol/"),
            Pair("蔚蓝档案", "/index.php/topics/blue-archive/"),
            Pair("鸣潮", "/index.php/topics/wuthering-waves/"),
            Pair("黑神话", "/index.php/topics/black-myth/"),
            Pair("狩龙人拉格纳", "/index.php/topics/ragna-crimson/"),
            Pair("DARLING in the FRANXX", "/index.php/topics/darling-in-the-franxx/"),
            Pair("电锯人", "/index.php/topics/chainsaw-man/"),
            Pair("明日方舟", "/index.php/topics/arknights/"),
            Pair("路人女主的养成方法", "/index.php/topics/saekano/"),
            Pair("鬼刀", "/index.php/topics/ghostblade/"),
            Pair("间谍过家家", "/index.php/topics/spyxfamily/"),
            Pair("小红帽", "/index.php/topics/little-red-riding-hood/"),
            Pair("约会大作战", "/index.php/topics/date-a-live/"),
            Pair("彻夜之歌", "/index.php/topics/call-of-the-night/"),
            Pair("守望先锋", "/index.php/topics/overwatch/"),
            Pair("崩坏3", "/index.php/topics/honkai-3rd/"),
            Pair("Vtuber", "/index.php/topics/vtuber/"),
            Pair("少女前线", "/index.php/topics/girls-frontline/"),
            Pair("拳皇", "/index.php/topics/king-of-fighters/"),
            Pair("超级索尼子", "/index.php/topics/super-sonico/"),
            Pair("最终幻想", "/index.php/topics/final-fantasy/"),
            Pair("SSSS.电光机王", "/index.php/topics/ssss-dynazenon/"),
            Pair("黑兽", "/index.php/topics/kuroinu/"),
            Pair("深空之眼", "/index.php/topics/aether-gazer/"),
            Pair("黑帝斯", "/index.php/topics/hades/"),
            Pair("青春猪头少年不会梦到兔女郎学姐", "/index.php/topics/seishun-buta-yarou-wa-bunny-girl-senpai-no-yume-o-minai/"),
            Pair("Hololive", "/index.php/topics/hololive/"),
            Pair("街头霸王", "/index.php/topics/street-fighter/"),
            Pair("葬送的芙莉莲", "/index.php/topics/frieren-beyond-journey-s-end/"),
            Pair("埃罗芒阿老师", "/index.php/topics/eromanga-sensei/"),
            Pair("请问您今天要来点兔子吗？", "/index.php/topics/is-the-order-a-rabbit/"),
            Pair("缘之空", "/index.php/topics/yosuga-no-sora/"),
            Pair("未麻的部屋", "/index.php/topics/perfect-blue/"),
            Pair("铁甲小宝", "/index.php/topics/b-robo-kabutack/"),
            Pair("杀戮都市", "/index.php/topics/gantz/"),
            Pair("憧憬成为魔法少女", "/index.php/topics/gushing-over-magical-girls/"),
            Pair("绝区零", "/index.php/topics/zenless-zone-zero/"),
            Pair("火影忍者", "/index.php/topics/naruto/"),
            Pair("精灵宝可梦", "/index.php/topics/pokemon/"),
            Pair("终末的女武神", "/index.php/topics/record-of-ragnarok/"),
            Pair("薇薇-萤石眼之歌", "/index.php/topics/vivy-fluorite-eyes-song/"),
            Pair("铁拳", "/index.php/topics/tekken/"),
            Pair("魔法少女☆伊莉雅", "/index.php/topics/fate-kaleid-liner-prisma-illya/"),
            Pair("Mirror", "/index.php/topics/mirror/"),
            Pair("King Exit", "/index.php/topics/king-exit/"),
            Pair("美少女万华镜", "/index.php/topics/bishoujo-mangekyou/"),
            Pair("Eternal Fantasy", "/index.php/topics/eternal-fantasy/"),
            Pair("翠之海", "/index.php/topics/endless-jade-sea/"),
            Pair("恶魔战士", "/index.php/topics/darkstalkers/"),
            Pair("胆大党", "/index.php/topics/dandadan/"),
            Pair("进击的巨人", "/index.php/topics/attack-on-titans/"),
            Pair("艳娘幻梦谭", "/index.php/topics/enjou-genmu-tan/"),
            Pair("海贼王", "/index.php/topics/one-piece/"),
            Pair("新世纪福音战士", "/index.php/topics/neon-genesis-evangelion/"),
            Pair("触手和巫女", "/index.php/topics/tentacle-and-witches/"),
            Pair("不时轻声地以俄语遮羞的邻座艾莉同学", "/index.php/topics/roshidere/"),
            Pair("姐姐般的存在", "/index.php/topics/ane-naru-mono/"),
            Pair("猫娘乐园", "/index.php/topics/nekopara/"),
            Pair("孤独摇滚", "/index.php/topics/bocchi-the-rock/"),
            Pair("公主连结", "/index.php/topics/princess-connect/"),
            Pair("不死者之王", "/index.php/topics/overlord/"),
            Pair("狂赌之渊", "/index.php/topics/kakegurui/"),
            Pair("出包王女", "/index.php/topics/to-love-ru/"),
            Pair("多娜多娜", "/index.php/topics/dohna-dohna/"),
            Pair("棕色尘埃", "/index.php/topics/brown-dust/"),
            Pair("机动战士高达", "/index.php/topics/gundam/"),
            Pair("重返未来：1999", "/index.php/topics/reverse-1999/"),
            Pair("舰队收藏", "/index.php/topics/kantai-collection/"),
            Pair("碧蓝幻想", "/index.php/topics/grandblue-fantasy/"),
            Pair("莱莎的炼金工坊", "/index.php/topics/atelier-ryza/"),
            Pair("偶像大师", "/index.php/topics/the-idolmaster/"),
            Pair("我推的孩子", "/index.php/topics/oshi-no-ko/"),
            Pair("赛马娘", "/index.php/topics/uma-musume/"),
            Pair("无期迷途", "/index.php/topics/path-to-nowhere/"),
            Pair("亚当斯一家", "/index.php/topics/the-addams-family/"),
            Pair("空之境界", "/index.php/topics/kara-no-kyoukai/"),
            Pair("关于我在无意间被隔壁的天使变成废人这件事", "/index.php/topics/otonari-no-tenshi-sama-ni-itsunomanika-dame-ningen-ni-sareteita-ken/"),
            Pair("人形电脑天使心", "/index.php/topics/chobits/"),
            Pair("魔法少女小圆", "/index.php/topics/puella-magi-madoka-magica/"),
            Pair("吊带袜天使", "/index.php/topics/panty-and-stocking-with-garterbelt/"),
            Pair("喵斯快跑", "/index.php/topics/muse-dash/"),
            Pair("东方Project", "/index.php/topics/touhou-project/"),
            Pair("罪恶王冠", "/index.php/topics/guilty-crown/"),
            Pair("命运之子", "/index.php/topics/destiny-child/"),
            Pair("在地下城寻求邂逅是否搞错了什么", "/index.php/topics/is-it-wrong-to-try-to-pick-up-girls-in-a-dungeon/"),
            Pair("王者荣耀", "/index.php/topics/honor-of-kings/"),
            Pair("莉可丽丝", "/index.php/topics/lycoris-recoil/"),
            Pair("干物妹！小埋", "/index.php/topics/himouto-umaru-chan/"),
            Pair("工作细胞", "/index.php/topics/cells-at-work/"),
            Pair("喜羊羊与灰太狼", "/index.php/topics/pleasant-goat-and-big-big-wolf/"),
            Pair("败犬女主太多了！", "/index.php/topics/too-many-losing-heroines/"),
            Pair("地狱老师", "/index.php/topics/hell-teacher-nube/"),
            Pair("SSSS.GRIDMAN", "/index.php/topics/ssss-gridman/"),
            Pair("精灵村", "/index.php/topics/elf-mura/"),
            Pair("合金装备", "/index.php/topics/metal-gear/"),
            Pair("一拳超人", "/index.php/topics/one-punch-man/"),
            Pair("魔物娘的同居日常", "/index.php/topics/monster-museum/"),
            Pair("鬼灭之刃", "/index.php/topics/demon-slayer/"),
            Pair("生化危机", "/index.php/topics/resident-evil/"),
        ),
    )

    private class ModelFilter : UriPartFilter(
        "模特",
        arrayOf(
            Pair("全部", ""),
            // 基于常见的写真模特分类
            Pair("日本模特", "/index.php/models/japanese/"),
            Pair("韩国模特", "/index.php/models/korean/"),
            Pair("中国模特", "/index.php/models/chinese/"),
            Pair("欧美模特", "/index.php/models/western/"),
            Pair("Cosplay模特", "/index.php/models/cosplay/"),
            Pair("网络红人", "/index.php/models/internet-celebrity/"),
            Pair("专业模特", "/index.php/models/professional/"),
            Pair("业余模特", "/index.php/models/amateur/"),
            Pair("新人模特", "/index.php/models/newcomer/"),
            Pair("知名模特", "/index.php/models/famous/"),
        ),
    )

    /**
     *创建选择过滤器的类。 下拉菜单中的每个条目都有一个名称和一个显示名称。
     *如果选择了一个条目，它将作为查询参数附加到URI的末尾。
     *如果将firstIsUnspecified设置为true，则如果选择了第一个条目，则URI不会附加任何内容。
     */
    // vals: <name, display>
    private open class UriPartFilter(
        displayName: String,
        val vals: Array<Pair<String, String>>,
        defaultValue: Int = 0,
    ) :
        Filter.Select<String>(displayName, vals.map { it.first }.toTypedArray(), defaultValue) {
        open fun toUriPart() = vals[state].second
    }

    override fun setupPreferenceScreen(screen: PreferenceScreen) {
        addRandomUAPreferenceToScreen(screen)

        // 添加登录设置
        androidx.preference.EditTextPreference(screen.context).apply {
            key = LoginInterceptor.LOGIN_USERNAME_PREF
            title = "用户名"
            summary = "输入您的用户名或邮箱"
            setDefaultValue("")
            setOnBindEditTextListener { editText ->
                editText.inputType = android.text.InputType.TYPE_CLASS_TEXT
            }
        }.also(screen::addPreference)

        androidx.preference.EditTextPreference(screen.context).apply {
            key = LoginInterceptor.LOGIN_PASSWORD_PREF
            title = "密码"
            summary = "输入您的登录密码"
            setDefaultValue("")
            setOnBindEditTextListener { editText ->
                editText.inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
            }
        }.also(screen::addPreference)
    }
    companion object {
        private const val PREFIX_ID_SEARCH_NO_COLON = "MT"
        const val PREFIX_ID_SEARCH = "$PREFIX_ID_SEARCH_NO_COLON:"
    }
}

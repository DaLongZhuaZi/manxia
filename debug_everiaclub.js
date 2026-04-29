// ============================================================
// Everia.club 详情页深度调试
// 打开任意 gallery 详情页后粘贴执行
// ============================================================
(function() {
  // --- 1. .mainleft 内部结构分析 ---
  var mainleft = document.querySelector('.mainleft');
  console.log('===== .mainleft 子元素结构 =====');
  if (mainleft) {
    Array.from(mainleft.children).forEach(function(child, i) {
      var imgs = child.querySelectorAll('img');
      var links = child.querySelectorAll('a');
      var cls = child.className || '';
      var id = child.id || '';
      console.log(
        '[' + i + '] <' + child.tagName.toLowerCase() + '>' +
        (id ? ' #' + id : '') +
        (cls ? ' .' + cls.substring(0, 40) : '') +
        ' | imgs:' + imgs.length +
        ' | links:' + links.length +
        ' | text:' + (child.textContent || '').trim().substring(0, 60)
      );
    });
  }

  // --- 2. 查找 gallery 内容区域的精确选择器 ---
  console.log('\n===== 候选内容区域选择器 =====');
  var candidates = [
    '.mainleft .article-content',
    '.mainleft .entry-content',
    '.mainleft .post-content',
    '.mainleft article',
    '.mainleft .content',
    '.mainleft .gallery',
    '.mainleft .article',
    '.mainleft .leftp',
    '.mainleft .single-content',
    '.mainleft .detail',
    '.mainleft .images',
    '.mainleft .pic',
    '.mainleft center',
    '.mainleft .wp-block-gallery',
    '.mainleft figure',
    '.mainleft p img',
    '.mainleft div > img'
  ];
  candidates.forEach(function(sel) {
    var els = document.querySelectorAll(sel);
    if (els.length > 0) {
      var imgCount = 0;
      els.forEach(function(el) { imgCount += el.querySelectorAll('img').length; });
      console.log(sel + ' -> ' + els.length + ' 个元素, 含 ' + imgCount + ' 张图片');
    }
  });

  // --- 3. 按图片尺寸区分 ---
  console.log('\n===== 图片尺寸分布 =====');
  var allImgs = document.querySelectorAll('.mainleft img');
  var sizeGroups = {};
  allImgs.forEach(function(img) {
    var w = img.naturalWidth;
    var h = img.naturalHeight;
    var key = w + 'x' + h;
    if (!sizeGroups[key]) sizeGroups[key] = { count: 0, src: '' };
    sizeGroups[key].count++;
    if (!sizeGroups[key].src) sizeGroups[key].src = (img.getAttribute('src') || '').substring(0, 80);
  });
  Object.keys(sizeGroups).forEach(function(key) {
    console.log(key + ' -> ' + sizeGroups[key].count + ' 张 | 示例: ' + sizeGroups[key].src);
  });

  // --- 4. 父容器层级追踪（第一张大图） ---
  console.log('\n===== 大图父容器层级 =====');
  var firstBigImg = null;
  allImgs.forEach(function(img) {
    if (!firstBigImg && img.naturalWidth > 500) firstBigImg = img;
  });
  if (firstBigImg) {
    var el = firstBigImg;
    var path = [];
    while (el && el !== document.body) {
      var tag = el.tagName.toLowerCase();
      var c = el.className || '';
      var id = el.id || '';
      path.push(tag + (id ? '#' + id : '') + (c ? '.' + c.substring(0, 30).replace(/\s+/g, '.') : ''));
      el = el.parentElement;
    }
    console.log('大图路径: ' + path.join(' > '));
  }

  // --- 5. 所有 img 标签详情（带父元素信息） ---
  console.log('\n===== 全部 .mainleft img 详情 =====');
  var imgDetails = [];
  allImgs.forEach(function(img, i) {
    var parent = img.parentElement;
    var grandparent = parent ? parent.parentElement : null;
    imgDetails.push({
      i: i,
      w: img.naturalWidth,
      h: img.naturalHeight,
      parentTag: parent ? parent.tagName : '',
      parentClass: parent ? (parent.className || '').substring(0, 30) : '',
      gpTag: grandparent ? grandparent.tagName : '',
      gpClass: grandparent ? (grandparent.className || '').substring(0, 30) : '',
      src: (img.getAttribute('src') || '').substring(0, 100)
    });
  });
  console.table(imgDetails);

  // --- 6. h1 和标题 ---
  console.log('\n===== 标题信息 =====');
  var h1 = document.querySelector('h1');
  var ogTitle = document.querySelector('meta[property="og:title"]');
  console.log('h1:', h1 ? h1.textContent.trim().substring(0, 100) : '(无)');
  console.log('og:title:', ogTitle ? ogTitle.getAttribute('content') : '(无)');

  // --- 7. 汇总 ---
  console.log('\n===== 汇总 =====');
  console.log(JSON.stringify({
    url: location.href,
    mainleftChildren: mainleft ? mainleft.children.length : 0,
    totalImgs: allImgs.length,
    h1: h1 ? h1.textContent.trim().substring(0, 60) : null
  }));
})();

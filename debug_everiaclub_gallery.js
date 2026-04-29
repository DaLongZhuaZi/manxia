// ============================================================
// Everia.club 详情页图片提取调试
// 在 gallery 详情页（如 https://www.everiaclub.com/2026/04/29/xxx）粘贴执行
// ============================================================
(function() {
  var result = {};

  // 1. 当前页面URL
  result.url = location.href;

  // 2. .mainleft 子元素结构
  var mainleft = document.querySelector('.mainleft');
  result.hasMainleft = !!mainleft;
  if (mainleft) {
    result.mainleftChildCount = mainleft.children.length;

    // 3. .mainleft > img（直接子元素）
    var directImgs = mainleft.querySelectorAll(':scope > img');
    result.directImgCount = directImgs.length;

    // 4. 详细分析每张直接子img
    var imgDetails = [];
    directImgs.forEach(function(img, i) {
      imgDetails.push({
        i: i,
        naturalW: img.naturalWidth,
        naturalH: img.naturalHeight,
        hasDataOriginal: img.hasAttribute('data-original'),
        hasDataLazySrc: img.hasAttribute('data-lazy-src'),
        hasDataSrc: img.hasAttribute('data-src'),
        dataOriginal: (img.getAttribute('data-original') || '').substring(0, 120),
        dataLazySrc: (img.getAttribute('data-lazy-src') || '').substring(0, 120),
        dataSrc: (img.getAttribute('data-src') || '').substring(0, 120),
        src: (img.getAttribute('src') || '').substring(0, 120),
        className: img.className
      });
    });
    result.directImgDetails = imgDetails;

    // 5. 所有 img（包括嵌套的）
    var allImgs = mainleft.querySelectorAll('img');
    result.allImgCount = allImgs.length;

    // 6. .mainleft .leftp > a 数量（列表页才有）
    var leftpLinks = mainleft.querySelectorAll('.leftp > a');
    result.leftpLinkCount = leftpLinks.length;
  }

  // 7. 测试当前选择器
  var selector1 = document.querySelectorAll('.mainleft > img');
  var selector2 = document.querySelectorAll('.mainleft > img[data-original]');
  var selector3 = document.querySelectorAll('.mainleft img');
  result.selectorResults = {
    'mainleft_gt_img': selector1.length,
    'mainleft_gt_img_data_original': selector2.length,
    'mainleft_img': selector3.length
  };

  // 8. 测试URL编码问题
  var testChapterId = '2026/04/29/test-gallery-name';
  var encoded1 = encodeURI(decodeURIComponent(testChapterId));
  result.urlEncodingTest = {
    input: testChapterId,
    encoded: encoded1,
    same: testChapterId === encoded1
  };

  console.log(JSON.stringify(result, null, 2));
  return JSON.stringify(result);
})();

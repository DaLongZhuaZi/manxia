// godamh.com test script
(async function() {
  var r = {
    url: location.href,
    title: document.title,
    search: {},
    links: [],
    api: []
  };

  // search input
  var inputs = document.querySelectorAll('input');
  r.searchInputs = [];
  for (var i = 0; i < inputs.length; i++) {
    var inp = inputs[i];
    r.searchInputs.push({
      type: inp.type,
      name: inp.name,
      id: inp.id,
      placeholder: inp.placeholder,
      className: inp.className
    });
  }

  // all links
  var links = document.querySelectorAll('a[href]');
  for (var j = 0; j < links.length && j < 50; j++) {
    r.links.push({
      text: links[j].textContent.trim().substring(0, 40),
      href: links[j].href
    });
  }

  // scripts src
  var scripts = document.querySelectorAll('script[src]');
  r.scripts = [];
  for (var k = 0; k < scripts.length; k++) {
    r.scripts.push(scripts[k].src);
  }

  console.log(JSON.stringify(r, null, 2));
  window._godamhResult = r;
  alert('done, check console');
})();

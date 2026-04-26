// CloudFront Function: ディレクトリ末尾スラッシュを index.html に書き換える
// /blog/    → /blog/index.html
// /docs/    → /docs/index.html
// /         → /index.html  (default_root_object と挙動が重複するが害はない)
function handler(event) {
  var request = event.request;
  var uri = request.uri;

  if (uri.endsWith('/')) {
    request.uri += 'index.html';
  }

  return request;
}

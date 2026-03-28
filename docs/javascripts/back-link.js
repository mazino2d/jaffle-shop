document$.subscribe(function () {
  var backLink = document.querySelector(".md-post__back a");
  if (backLink) {
    backLink.href = new URL("../../", window.location.href).href;
  }
});

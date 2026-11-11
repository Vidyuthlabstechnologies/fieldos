// guide.html: the chapter buttons jump the video to their time.
document.querySelectorAll('.chapters button').forEach(function (b) {
  b.addEventListener('click', function () {
    var v = document.getElementById('guide');
    v.currentTime = parseFloat(b.dataset.t);
    v.play();
  });
});

var page = new WebPage();
var system = require("system");
page.paperSize = {
  format: "A4",
  orientation: "portrait",
  margin: {
    left: "2cm",
    right: "2cm",
    top: "2cm",
    bottom: "1.75cm"
  },
  footer: {
    height: "0.4cm",
    contents: phantom.callback(function(pageNum, numPages) {
      return "<div style='text-align: right; font-family: sans-serif; font-size: 12px;'>" +
        pageNum + " / " + numPages + "</div>";
    })
  }
};

page.zoomFactor = 1.0;
page.open(system.args[1], function (status) {
  setTimeout(function() {
    page.render(system.args[2]);
    phantom.exit();
  }, 1000);
});

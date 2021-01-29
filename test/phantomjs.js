var page = require('webpage').create();
var postBody = 'auto=y&server=localhost%3A5909&users=5&mode=ten&host=35.184.10.104&close=force'

page.open('http://35.184.10.104/test.html', 'POST', postBody, function(status) {
  console.log("Status: " + status);
  if(status === "success") {
    page.render('example.png');
  }
  phantom.exit();
});

function gotoURL (link){
  window.location.href = link;
}


function decompress(inVal) {
 // var inVal = document.tmpForm.inVal.value;

  return pako.inflate(window.atob(inVal), { to: 'string'});
}

function compress() {
  var inVal = document.tmpForm.out.value;
  var outVal = window.btoa(pako.gzip(inVal, { to: 'string' }));
  document.tmpForm.inVal.value=outVal
}
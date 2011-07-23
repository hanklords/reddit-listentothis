var css = '\
.listen {padding-left:0} \
.next, .previous {color: #888888; font-weight: bold; padding:0px 1px} \
.listening {background-color:#F8E0EC} \
'

var style = document.createElement('style')
style.setAttribute('type', 'text/css')
style.appendChild(document.createTextNode(css))
document.getElementsByTagName('head')[0].appendChild(style)

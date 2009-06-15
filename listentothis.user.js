// Copyright (c) 2009 Mael Clerambault <maelclerambault@yahoo.fr>
//
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
// CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
// TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
// SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

// ==UserScript==
// @name           listentothis
// @include        http://www.reddit.com/r/listentothis*
// @description    Render /r/listentothis into a playlist.
// @copyright 2009, Mael Clerambault <maelclerambault@yahoo.fr>
// @require        jquery.js
// ==/UserScript==

$(function() {
  GM_addStyle(".listen {padding-left:0} .next, .previous {color: #888888; font-weight: bold; padding:0px 1px;} .listening {background-color:#F8E0EC}")

  function setPlayer(links) {
    $(".side").prepend(
      "<div class=\"spacer\"><div class=\"sidebox listen\">\
      <audio controls=\"true\" src=\"" + links[0] + "\"></audio>\
      <div ><a href=\"#\" class=\"previous\">(prev)|&lt;-</a><a href=\"#\" class=\"next\">&gt;| (next)</a></div>\
      <div class=\"subtitle\"><a href=\"http://yieu.eu/listentothis/playlist.rss\">Podcast</a></div>\
      <div class=\"subtitle\"><a href=\"http://yieu.eu/listentothis/playlist.m3u\">Playlist</a></div>\
      </div></div>"
    )

    function play(src) {
      $("audio").attr("src", src)
      $("audio")[0].load()
      $("audio")[0].play()
    }

    function previous() {
      current = $.inArray($("audio").attr("src"), links)
      if(current == 0) {
        current = links.length
      }
      play(links[current - 1])
    }

    function next() {
      current = $.inArray($("audio").attr("src"), links)
      if(current == links.length - 1) {
        current = -1
      }
      play(links[current + 1])
    }

    //  $("audio").bind("error", function(event) {next() })
    $("audio").bind("ended", function(event) {next()})
    $("audio").bind("play", function(event) {
      $("div.link").removeClass("listening")
      $("div.link:has(a[href=\"" + this.src + "\"])").addClass("listening")
    })

    $(".previous").click(previous)
    $(".next").click(next)
    $(".previous, .next").click(function(event) {event.preventDefault()})
  }

  GM_xmlhttpRequest({
    method: "GET",
    url: "http://yieu.eu/listentothis/playlist.json",
    onload: function(r) {
      var links = [];
      known = $.map(eval(r.responseText), function(e) {return "http://yieu.eu/listentothis/" + e + ".ogg"})

      $("div.link").each(function(i) {
        var href = $("a.comments", this).attr("href").split("/")
        var name = href[href.length - 2]
        var link = "http://yieu.eu/listentothis/" + name + ".ogg"
        if($.inArray(link, known) != -1) {
          links.push(link);
          $("ul.buttons", this).append("<li><a class=\"ogglink\" href=\"" + link + "\">Download</a></li>")
        }
      })

      if(links.length > 0) {
        setPlayer(links)
      }
    }
  })
})


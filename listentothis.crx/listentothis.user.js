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
// @include        http://www.reddit.com/r/Music*
// @description    Render /r/listentothis into a playlist.
// @copyright      2009, Mael Clerambault <maelclerambault@yahoo.fr>
// @require        jquery.js
// @resource       css listentothis.css
// @version        0.3
// ==/UserScript==

site =  "http://yieu.eu/listentothis/"
audio = null

function setPlayer(links) {
  var subreddit = $(".pagename").text()

  $(".side").prepend(
    "<div class=\"spacer\"><div class=\"sidebox listen\">\
    <audio controls=\"true\" src=\"" + links[0] + "\"></audio>\
    <div><a href=\"#\" class=\"previous\">(prev) |&lt;</a><a href=\"#\" class=\"next\">&gt;| (next)</a></div>\
    <div class=\"subtitle playing\">Playing:</div>\
    <div class=\"subtitle\">\
      Podcast :\
      <a href=\"" + site + subreddit + "_new.rss\">New</a>\
      <a href=\"" + site + subreddit + "_day.rss\">Today</a>\
      <a href=\"" + site + subreddit + "_week.rss\">Weekly</a>\
      <a href=\"" + site + subreddit + "_month.rss\">Monthly</a>\
      <a href=\"" + site + subreddit + "_all.rss\">All</a>\
    </div>\
    <div class=\"subtitle\">\
      Playlist :\
      <a href=\"" + site + subreddit + "_new.m3u\">New</a>\
      <a href=\"" + site + subreddit + "_day.m3u\">Today</a>\
      <a href=\"" + site + subreddit + "_week.m3u\">Weekly</a>\
      <a href=\"" + site + subreddit + "_month.m3u\">Monthly</a>\
      <a href=\"" + site + subreddit + "_all.m3u\">All</a>\
    </div>\
    </div></div>"
  )
  audio = $("audio")[0]
  audio.playlist = links
  audio.orig_play = audio.play
  audio.play = function(src) {
    this.src = src
    this.load()
    this.orig_play()
  }

  audio.previous = function() {
    var current = $.inArray(decodeURI(this.src), this.playlist)
    if(current == 0) { current = this.playlist.length }
    this.play(this.playlist[current - 1])
  }

  audio.next = function() {
    var current = $.inArray(decodeURI(this.src), this.playlist)
    if(current == this.playlist.length - 1) { current = -1 }
    this.play(this.playlist[current + 1])
  }

  $("audio").bind("ended", function() {audio.next()})
  $("audio").bind("play", function() {
    $("div.link").removeClass("listening")
    var item = $("div.link:has(a[href='" + decodeURI(this.src) + "'])")
    item.addClass("listening")
    $("div.playing").text("Playing: " + $(".listening a.title").text())
  })

  $(".previous").click(function() {audio.previous() })
  $(".next").click(function () {audio.next() })
  $(".previous, .next").click(function(event) {event.preventDefault()})
}

function load(msg) {
  var known = $.map(JSON.parse(msg), function(e) {return site + e + ".ogg"})
  var links = []

  $("div.link").each(function(i) {
    var href = $("a.comments", this).attr("href").split("/")
    var name = href[href.length - 2]
    var link = site + name + ".ogg"

    if($.inArray(link, known) != -1) {
      links.push(link);
      $("ul.buttons", this).append("<li><a class=\"ogglink\" href=\"" + link + "\">Play</a></li>")
    }
  })

  if(links.length > 0) { setPlayer(links) }
  $("a.ogglink").click(function(event) {
    audio.play(this.href)
    event.preventDefault()
  })
}

$(function() {
  if(typeof chrome == 'function') {
    chrome.extension.connect().onMessage.addListener(load)
  } else if(typeof GM_xmlhttpRequest == 'function') {
    GM_addStyle(GM_getResourceText("css"))
    GM_xmlhttpRequest({
      method: "GET",
      url: site + "playlist.json",
      onload: function(r) { load(r.responseText) }
    })
  }
})


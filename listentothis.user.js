// ==UserScript==
// @name           listentothis
// @include        http://www.reddit.com/r/listentothis/*
// @require        jquery.js
// ==/UserScript==

$(function() {
  GM_addStyle(".listen {padding-left:0} .listening {background-color:#F8E0EC}");

  var links = [];
  $("div.link").each(function(i) {
    var href = $("a.comments", this).attr("href").split("/");
    var name = href[href.length - 2];
    var link = "http://yieu.eu/listentothis/" + name + ".ogg";
    links.push(link);
    $("ul.buttons", this).append("<li><a class=\"ogglink\" href=\"" + link + "\">Direct link</a></li>");
  });
  
  $(".side").prepend(
    "<div class=\"spacer\"><div class=\"sidebox listen\">\
    <audio controls=\"true\" src=\"" + links[0] + "\"></audio>\
    <div class=\"subtitle\"><a href=\"#\" class=\"previous\">&lt;-</a> <a href=\"#\" class=\"next\">-&gt;</a></div>\
    <div class=\"subtitle\"><a href=\"http://yieu.eu/listentothis/playlist.rss\">Podcast</a></div>\
    <div class=\"subtitle\"><a href=\"http://yieu.eu/listentothis/playlist.m3u\">Playlist</a></div>\
    </div></div>"
  )

  $("audio").bind("play", function(event) {
    $("div.link").removeClass("listening")
    $("div.link:has(a[href=\"" + this.src + "\"])").addClass("listening")
  })

  $("audio").bind("error", function(event) {next() })
  $("audio").bind("ended", function(event) {next() })

  function previous(event) {
    current = $.inArray($("audio").attr("src"), links)
    $("audio").attr("src", links[current - 1])
    $("audio").get(0).load()
    $("audio").get(0).play()
  }

  function next(event) {
    current = $.inArray($("audio").attr("src"), links)
    $("audio").attr("src", links[current + 1])
    $("audio").get(0).load()
    $("audio").get(0).play()
  }

  $(".previous").click(function(event) {
    previous()
    event.preventDefault()
  })

  $(".next").click(function(event) {
    next()
    event.preventDefault()
  })
  
});


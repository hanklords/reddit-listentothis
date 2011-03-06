#!/usr/bin/env ruby

# Copyright (c) 2009 Mael Clerambault <maelclerambault@yahoo.fr>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'cgi'
require 'tmpdir'
require 'net/http'
require 'time'
require 'json'
require 'ogginfo'

RUNFILE="#{Dir.tmpdir}/#{ENV['LOGNAME']}_listentothis"
exit if File.exist?(RUNFILE)
FileUtils.touch(RUNFILE)

TRANSCODE="ffmpeg -v -1 -i \"%s\" -vn -f wav - 2> /dev/null | oggenc -Q -o \"%s\" -"
ROOT_SITE="http://yieu.eu/listentothis"
ROOT_FOLDER="#{ENV['HOME']}/www/listentothis"
HISTORY_NUMBER=100

class LastFMmp3
  PL="http://ws.audioscrobbler.com/2.0/?method=playlist.fetch&api_key=da6ae1e99462ee22e81ac91ed39b43a4&playlistURL=lastfm://playlist/track/%s&streaming=true"

  attr_reader :id, :media_url, :cookie
  def initialize(url)
    lastfm_page = Nokogiri::HTML.parse(open(URI.parse(url)))
    scripts = lastfm_page.search('script').text
    @id = scripts[/"id":"?(\d+)"?/, 1]
    playlist_url = PL % [@id]
    r = Net::HTTP.get_response(URI.parse(playlist_url))
    @cookie = r['Set-Cookie'][/AnonSession=([\w\d]+);/,1]
    playlist = Nokogiri.parse(r.body)
    @media_url = playlist.search('freeTrackURL', playlist.root.collect_namespaces).text
    if @media_url.empty?
      @media_url = playlist.search('location', playlist.root.collect_namespaces).text
    end
  end

  def media_io
    open(@media_url, "rb", {'Cookie' => "AnonSession=#@cookie;"})
  end
end

class Item
  class UnknownSource < StandardError; end
  def self.create(rss_node)
    content = rss_node.at('description').content
    d = Nokogiri::HTML(CGI.unescape(content))
    url = nil
    d.search('a').each {|a|
      next if not a.content == '[link]'
      url = URI.escape(a['href'])
      break
    }

    klass = case url
      when /\.ogg$/
        OggItem
      when /\.mp3$/
        MP3Item
      when /youtube.com/
        YoutubeItem
      when /soundcloud.com/
        SoundcloudItem
      when /jamendo.com.*album/
        JamendoAlbumItem
      when /last\.fm\//
        LastFMItem
      else
        raise UnknownSource.new(url)
    end

    klass.new(rss_node, url)
  end

  attr_reader :name, :url, :source, :title
  def initialize(rss_node, url)
    @rss_node = rss_node
    @source = url
    @title = rss_node.at('title').content
    @name  = rss_node.at('guid').content.split('/').last
    @url = "#{ROOT_SITE}/#@name.ogg"
    @file = "#{ROOT_FOLDER}/#@name.ogg"
  end

  def process; true end
  def valid?; File.file? @file end

  def to_m3u
    length = OggInfo.open(@file) {|ogg| ogg.length.to_i}
    "#EXTINF:#{length},#@title\n#@url\n"
  end

  def to_rss
    rss = @rss_node.dup
    rss.at('pubDate').content = Time.parse(rss.at('pubDate').content).rfc822
    rss.at('guid').content = @url
    enclosure = Nokogiri::XML::Node.new('enclosure', rss.document)
    enclosure['url'] = @url
    enclosure['type'] = "audio/ogg"
    enclosure['length'] = File.size(@file).to_s
    rss << enclosure
    rss
  end
end

class YoutubeItem < Item
  YOUTUBE_DL="youtube-dl -qo \"%s\" \"%s\""
  def process
    if not valid?
      puts @title
      video = "#{Dir.tmpdir}/youtube.video"
      system(YOUTUBE_DL % [video, @source])
      system(TRANSCODE % [video, @file])
      FileUtils.rm video, :force => true
    end
  end
end

class SoundcloudItem < Item
  def process
    if not valid?
      doc = Nokogiri::HTML.parse(open(@source))
      json_txt = doc.at("script:contains('bufferTracks.push')").text.sub("window.SC.bufferTracks.push(", "").sub(/\);$/, "")
      json = JSON.parse json_txt
      uri = json["streamUrl"]
      raw = "#{Dir.tmpdir}/youtube.video"
      open(raw, "wb") {|lf| lf.write open(uri).read}
      system(TRANSCODE % [raw, @file])
      FileUtils.rm raw, :force => true
    end
  end
end

class LastFMItem < Item
  def process
    if not valid?
      lfm = LastFMmp3.new(@source)
      mp3 = "#{Dir.tmpdir}/#{lfm.id}.mp3"
      open(mp3, "wb") {|f| f.write lfm.media_io.read }
      system(TRANSCODE % [mp3, @file])
      FileUtils.rm mp3, :force => true
    end
  end
end

class JamendoAlbumItem < Item
  Plain="http://api.jamendo.com/get2/stream/track/plain/?album_id=%s&order=numalbum_asc"
  def initialize(*args)
    super(*args)
    @id = @source[/album\/(\d+)/, 1]
    @m3u_url = "http://api.jamendo.com/get2/stream/track/m3u/?album_id=#{@id}&order=numalbum_asc"
  end

  def to_m3u
    open(@m3u_url).read.sub(/^#EXTM3U$/, '')
  end

  def to_rss
    items = open(Plain % [@id]).readlines.collect {|line|
      enclosure = Nokogiri::XML::Node.new('enclosure', rss.document)
      enclosure['url'] = line
      enclosure['type'] = "audio/mpeg"

      @rss_node.dup << enclosure
    }
    Nokogiri::XML::NodeSet.new(rss.document, items)
  end
end

class MP3Item < Item
  def process
    if not valid?
      mp3 = "#{Dir.tmpdir}/#@name.mp3"
      open(mp3, "wb") {|f| f.write open(@source, "rb").read }
      system(TRANSCODE % [mp3, @file])
      FileUtils.rm mp3, :force => true
    end
  end
end

class OggItem < Item
  def process
    if not valid?
      open(@file, "wb") {|f| f.write open(@source, "rb").read }
    end
  end
end

class Playlist
  attr_reader :subreddit, :order
  def initialize(rss_file)
    @playlist = []
    @items = []
    path, @subreddit, @order = *rss_file.match(%r{/r/(\w+)/.*\?\w+=(\w+)})

    @doc = Nokogiri::XML(open(rss_file))
    @doc.search('rss channel item').each { |rss_item|
      begin
        @items << Item.create(rss_item)
      rescue Item::UnknownSource => e
        p e
        next
      end
    }
  end
  
  def process
    @items.each_slice(5) do |items|
      items.each {|item| fork {item.process} }
      Process.waitall
    end
    @playlist = @items.select {|item| item.valid? }
  end

  def to_m3u
    "#EXTM3U\n" + @playlist.collect {|i| i.to_m3u }.join
  end

  def to_rss
    rss = @doc.dup
    rss.search('item').each {|rss_item| rss_item.remove }
    @playlist.each {|i| rss.at('channel') << i.to_rss  }
    rss.to_s
  end

  def names; @playlist.map {|i| i.name} end
  def to_a; @playlist end
end

begin

module SubReddit
  NEW = "http://www.reddit.com/r/%s/new.rss?sort=new&limit=#{HISTORY_NUMBER}"
  TODAY = "http://www.reddit.com/r/%s/top.rss?t=day&limit=#{HISTORY_NUMBER}"
  WEEK = "http://www.reddit.com/r/%s/top.rss?t=week&limit=#{HISTORY_NUMBER}"
  MONTH = "http://www.reddit.com/r/%s/top.rss?t=month&limit=#{HISTORY_NUMBER}"
  ALL = "http://www.reddit.com/r/%s/top.rss?t=all&limit=#{HISTORY_NUMBER}"
end

FileUtils.mkdir_p ROOT_FOLDER

items = Playlist.new("http://www.reddit.com/r/listentothis/new.rss?sort=new&limit=#{HISTORY_NUMBER}")
items.process

open("#{ROOT_FOLDER}/#{items.subreddit}_#{items.order}.m3u", "w") {|m3u| m3u.write items.to_m3u }
open("#{ROOT_FOLDER}/#{items.subreddit}_#{items.order}.rss", "w") {|rss| rss.write items.to_rss }
open("#{ROOT_FOLDER}/playlist.json", "w") {|json| json.write items.names.to_json }

# Clean folder
oggs = Dir.glob("#{ROOT_FOLDER}/*.ogg").each { |f|
  FileUtils.rm f ,:force => true if not items.names.include? File.basename(f, '.ogg')
}

ensure
  FileUtils.rm  RUNFILE,:force => true
end

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

$\="\n"
$,=" "
LOGFILE="#{ENV['HOME']}/.listentothis.rb.log"
ROOT_SITE="http://yieu.eu/listentothis"
ROOT_FOLDER="#{ENV['HOME']}/www/listentothis"
HISTORY_NUMBER=100
SUBREDDITS=%w{listentothis listentomusic EcouteCa dubstep Metal}

class Item
  TRANSCODE=%w{ffmpeg -i -vn -acodec libvorbis -ab 128k -ac 2}.freeze
  def self.create(url, title, name)
    klass = case url
      when /\.ogg$/
        OggItem
      when /\.mp3$/
        MP3Item
      when /youtube.com/
        YoutubeItem
      when /youtu.be/
        YoutubeShortItem
      when /soundcloud.com/
        SoundcloudItem
      else
        UnknownSource
    end

    klass.new(url, title, name)
  end

  attr_reader :source, :title, :name, :url
  def initialize(source, title, name)
    @source, @title, @name = source, title, name
    @url = "#{ROOT_SITE}/#@name.ogg"
    @file = "#{ROOT_FOLDER}/#@name.ogg"
    @disable = "#{ROOT_FOLDER}/#@name.disable"
  end

  def process; true end
  def valid?; File.file? @file end
  def tempfile
    tmpfile = "#{Dir.tmpdir}/#{ENV['LOGNAME']}_listentothis_#@name"
    begin
      yield tmpfile
    ensure
      FileUtils.rm  tmpfile,:force => true
    end
  end
  def transcode(source)
    i = TRANSCODE.index("-i")
    system(*TRANSCODE.dup.insert(i+1, source), @file, 2 => :close) 
  end

  def disable; FileUtils.touch @disable end
  def disabled?; File.file? @disable end

  def to_m3u
    length = OggInfo.open(@file) {|ogg| ogg.length.to_i}
    "#EXTINF:#{length},#@title\n#@url\n"
  end
end

class UnknownSource < Item
  def valid?; false end
  def disabled?; true end
end

class YoutubeItem < Item
  YOUTUBE_DL=%w{youtube-dl --max-quality=18 --no-part -r 1m -q -o}.freeze
  def process
    tempfile {|tmpfile|
      if system(*YOUTUBE_DL, tmpfile, @source, 2 => :close)
        transcode(tmpfile)
      else
        disable
      end
    }
  end
end

class YoutubeShortItem < YoutubeItem
  def process
    r = Net::HTTP.get_response(URI.parse(@source))
    @source = r["location"]
    super
  end
end

class SoundcloudItem < Item
  def process
    doc = Nokogiri::HTML.parse(open(@source))
    json_txt = doc.at("script:contains('bufferTracks.push')").text.sub("window.SC.bufferTracks.push(", "").sub(/\);$/, "")
    json = JSON.parse json_txt
    uri = json["streamUrl"]
    
    tempfile {|tmpfile|
      open(tmpfile, "w") {|f| f.write open(uri).read }
      transcode(tmpfile)
    }
  rescue
    disable
  end
end

class MP3Item < Item
  def process
    tempfile {|tmpfile|
      open(tmpfile, "w") {|f| f.write open(@source, "rb").read }
      transcode(tmpfile)
    }
  end
end

class OggItem < Item
  def process
    open(@file, "wb") {|f| f.write open(@source, "rb").read }
  end
end

class Playlist
  attr_reader :subreddit, :order, :valid, :disabled
  def initialize(json_file)
    @items = []
    path, @subreddit, @order = *json_file.match(%r{/r/(\w+)/.*\?\w+=(\w+)})

    @doc = JSON.parse(open(json_file).read)
    @doc["data"]["children"].each {|entry|
      entry = entry["data"]
      url, title, name = entry["url"], entry["title"], entry["permalink"].split('/').last
      @items << Item.create(url, title, name)
    }
  end
  
  def process
    logfile = open(LOGFILE, "a")
    begin_item = begin_subreddit = Time.now
    processed = 0
    logfile.print "subreddit:", @subreddit, @order
    @items.each do |item|
    begin
      next if item.valid? or item.disabled?
      begin_item = Time.now
      processed += 1
      item.process
      status = (UnknownSource === item || item.disabled?) ? "Failed" : "OK"
      logfile.print "item:", "%.0fs" % (Time.now - begin_item), item.name, item.source, item.class, status
    rescue
      logfile.print "item:", "%.0fs" % (Time.now - begin_item), item.name, item.source, item.class, "Failed"
      next
    end
    end
    
    @valid = @items.select {|item| item.valid? }
    @disabled = @items.select {|item| item.disabled? }
    open("#{ROOT_FOLDER}/#{@subreddit}_#{@order}.m3u", "w") {|m3u| m3u.write to_m3u }
    
    logfile.print "summary:", "%.0fs" % (Time.now - begin_subreddit), processed
    logfile.close
  end

  def to_m3u
    "#EXTM3U\n" + @valid.collect {|i| i.to_m3u }.join
  end

  def to_a; valid end
end

module SubReddit
  NEW = "http://www.reddit.com/r/%s/new.json?sort=new&limit=#{HISTORY_NUMBER}".freeze
  TODAY = "http://www.reddit.com/r/%s/top.json?t=day&limit=#{HISTORY_NUMBER}".freeze
  WEEK = "http://www.reddit.com/r/%s/top.json?t=week&limit=#{HISTORY_NUMBER}".freeze
  MONTH = "http://www.reddit.com/r/%s/top.json?t=month&limit=#{HISTORY_NUMBER}".freeze
  ALL = "http://www.reddit.com/r/%s/top.json?t=all&limit=#{HISTORY_NUMBER}".freeze
end

begin
begin_all = Time.now
open(LOGFILE, "a") {|logfile| logfile.print "begin:", begin_all}
FileUtils.mkdir_p ROOT_FOLDER

valid, disabled = [], []
SUBREDDITS.each do |subreddit|
  [SubReddit::NEW, SubReddit::TODAY, SubReddit::WEEK, SubReddit::MONTH, SubReddit::ALL].each {|url|
    items = Playlist.new(url % subreddit)
    items.process
    valid.concat items.valid.map {|i| i.name}
    disabled.concat items.disabled.map {|i| i.name}
  }
end
open("#{ROOT_FOLDER}/playlist.json", "w") {|json| json.write valid.uniq.to_json }

# Clean folder
Dir.glob("#{ROOT_FOLDER}/*.ogg").each { |f|
  FileUtils.rm f ,:force => true if not valid.include? File.basename(f, '.ogg')
}
Dir.glob("#{ROOT_FOLDER}/*.disable").each { |f|
  FileUtils.rm f ,:force => true if not disabled.include? File.basename(f, '.disable')
}

ensure
  open(LOGFILE, "a") {|logfile| logfile.print "end:", "%.0fs" % (Time.now - begin_all); logfile.print}
  FileUtils.rm  RUNFILE,:force => true
end

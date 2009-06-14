#!/usr/bin/env ruby

require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'cgi'
require 'tmpdir'
require 'net/http'
require 'time'
require 'json'

TRANSCODE="ffmpeg -i \"%s\" -vn -acodec vorbis -ac 2 -ab 192k -y \"%s\" 2> /dev/null"
ROOT_SITE="http://yieu.eu/listentothis"
ROOT_FOLDER="#{ENV['HOME']}/www/listentothis"

class YoutubeVideo
  FLV="http://www.youtube.com/get_video?video_id=%s&t=%s&el=detailpage&ps="

  attr_reader :video_id, :t, :media_url
  def initialize(url)
    youtube_page = open(url).read
    @t = youtube_page[/"t": *"([^\"]+)"/, 1]
    @video_id = youtube_page[/"video_id": *"([^\"]+)"/, 1]
    @media_url = FLV % [video_id, t]
  end

  def media_io; open(@media_url) end
end

class LastFMmp3
  PL="http://ws.audioscrobbler.com/2.0/?method=playlist.fetch&api_key=da6ae1e99462ee22e81ac91ed39b43a4&playlistURL=lastfm://playlist/track/%s&streaming=true"

  attr_reader :id, :media_url, :cookie
  def initialize(url)
    lastfm_page = Nokogiri::HTML.parse(open(URI.parse(url)))
    scripts = lastfm_page.search('script').text
    @id = scripts[/"id":"(\d+)"/, 1]
    playlist_url = PL % [@id]
    r = Net::HTTP.get_response(URI.parse(playlist_url))
    @cookie = r['Set-Cookie'][/AnonSession=([\w\d]+);/,1]
    playlist = Nokogiri.parse(r.body)
    @media_url = playlist.at('freeTrackURL', playlist.root.collect_namespaces).text
    if @media_url.empty?
      @media_url = playlist.at('location', playlist.root.collect_namespaces).text
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
      when /\.mp3$/
        MP3Item
      when /youtube.com/
        YoutubeItem
      when /jamendo.com.*album/
        JamendoAlbumItem
      when /last\.?fm/
        LastFMItem
      else
        raise UnknownSource.new(url)
    end

    klass.new(rss_node, url)
  end

  attr_reader :name, :url, :source
  def initialize(rss_node, url)
    @rss_node = rss_node
    @source = url
    @url = @source
    @title = rss_node.at('title').content
    @name  = rss_node.at('guid').content.split('/').last
  end

  def to_m3u
    "#EXTINF:-1,#@title\n#@url\n"
  end

  def to_rss
    rss = @rss_node.dup
    rss.at('pubDate').content = Time.parse(rss.at('pubDate').content).rfc822
    rss.at('guid').content = @url
    enclosure = Nokogiri::XML::Node.new('enclosure', rss.document)
    enclosure['url'] = @url
    enclosure['type'] = "audio/ogg"
    rss << enclosure
    rss
  end
end

class YoutubeItem < Item
  def initialize(*args)
    super(*args)
    @mp3_filename = "#{@name}.ogg"
    @url = "#{ROOT_SITE}/#{@mp3_filename}"
    mp3 = "#{ROOT_FOLDER}/#{@mp3_filename}"

    if not File.exist? mp3
      yt = YoutubeVideo.new(@source)
      flv = "#{Dir.tmpdir}/#{yt.video_id}.flv"
      open(flv, "wb") {|f| f.write yt.media_io.read}
      system(TRANSCODE % [flv, mp3])
      FileUtils.rm flv
    end
  end
end

class LastFMItem < Item
  def initialize(*args)
    super(*args)
    @mp3_filename = "#{@name}.ogg"
    @url = "#{ROOT_SITE}/#{@mp3_filename}"
    mp3 = "#{ROOT_FOLDER}/#{@mp3_filename}"

    if not File.exist? mp3
      lfm = LastFMmp3.new(@source)
      open(mp3, "wb") {|f|
        f.write lfm.media_io.read
      }
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
end

class Playlist
  def initialize(rss_file)
    @playlist = []

    @doc = Nokogiri.parse(open(rss_file))
    @doc.search('rss channel item').each { |rss_item|
      begin
        item = Item.create(rss_item)
        puts item.url
      rescue OpenURI::HTTPError, Item::UnknownSource => e
        p e
        next
      end
      @playlist << item
    }
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

  def to_a; @playlist end
  def to_json; @playlist.collect {|i| i.url }.to_json end
end

FileUtils.mkdir_p ROOT_FOLDER

items = Playlist.new('http://www.reddit.com/r/listentothis/new.rss?sort=new')
names = items.to_a.collect {|item| item.name }

open("#{Dir.tmpdir}/playlist.m3u", "w") {|m3u| m3u.write items.to_m3u }
FileUtils.mv "#{Dir.tmpdir}/playlist.m3u", "#{ROOT_FOLDER}/playlist.m3u"

open("#{Dir.tmpdir}/playlist.rss", "w") {|rss| rss.write items.to_rss }
FileUtils.mv "#{Dir.tmpdir}/playlist.rss", "#{ROOT_FOLDER}/playlist.rss"

open("#{Dir.tmpdir}/playlist.json", "w") {|json| json.write items.to_json }
FileUtils.mv "#{Dir.tmpdir}/playlist.json", "#{ROOT_FOLDER}/playlist.json"

# Clean folder
Dir.glob("#{ROOT_FOLDER}/*.ogg").sort_by {|f| test(?M, f)}.reverse[50..-1].each{|f|
  FileUtils.rm f ,:force => true
}


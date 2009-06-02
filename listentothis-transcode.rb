#!/usr/bin/env ruby

require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'cgi'
require 'tmpdir'
require 'net/http'

TRANSCODE="ffmpeg -i \"%s\" -acodec libmp3lame -ac 2 -ab 128k -y \"%s\" 2> /dev/null"
ROOT_SITE="http://yieu.eu/listentothis"
ROOT_FOLDER="#{ENV['HOME']}/www/listentothis"

class YoutubeVideo
  FLV="http://www.youtube.com/get_video?video_id=%s&t=%s&el=detailpage&ps="

  attr_reader :video_id, :t, :flv_url
  def initialize(url)
    youtube_page = Nokogiri.parse(open(url))
    scripts = youtube_page.search('script').text
    @t = scripts[/"t": *"([^\"]+)"/, 1]
    @video_id = scripts[/"video_id": *"([^\"]+)"/, 1]
    @flv_url = FLV % [video_id, t]
  end
end

class LastFMmp3
  PL="http://ws.audioscrobbler.com/2.0/?method=playlist.fetch&api_key=da6ae1e99462ee22e81ac91ed39b43a4&playlistURL=lastfm://playlist/track/%s&streaming=true"

  attr_reader :id, :mp3_url, :cookie
  def initialize(url)
    lastfm_page = Nokogiri.parse(open(URI.parse(url)))
    scripts = lastfm_page.search('script').text
    @id = scripts[/"id":"(\d+)"/, 1]
    playlist_url = PL % [@id]
    r = Net::HTTP.get_response(URI.parse(playlist_url))
    @cookie = r['Set-Cookie'][/AnonSession=([\w\d]+);/,1]
    playlist = Nokogiri.parse(r.body)
    @mp3_url = playlist.at('freeTrackURL', playlist.root.collect_namespaces).text
    if @mp3_url.empty?
      @mp3_url = playlist.at('location', playlist.root.collect_namespaces).text
    end
  end
end

def youtube_url(title, name, url)
  mp3_filename = "#{name}.mp3"
  mp3 = "#{ROOT_FOLDER}/#{mp3_filename}"

  if not File.exist? mp3
    yt = YoutubeVideo.new(url)
    flv = "#{Dir.tmpdir}/#{yt.video_id}.flv"
    open(flv, "wb") {|f| f.write open(yt.flv_url, "rb").read}
    system(TRANSCODE % [flv, mp3])
    FileUtils.rm flv
  end

  "#EXTINF:-1,#{title}\n#{ROOT_SITE}/#{mp3_filename}"
end

def lastfm_url(title, name, url)
  mp3_filename = "#{name}.mp3"
  mp3 = "#{ROOT_FOLDER}/#{mp3_filename}"

  if not File.exist? mp3
    yt = LastFMmp3.new(url)
    open(mp3, "wb") {|f|
      f.write open(yt.mp3_url, "rb", {'Cookie' => "AnonSession=#{yt.cookie};"}).read
    }
  end

  "#EXTINF:-1,#{title}\n#{ROOT_SITE}/#{mp3_filename}"
end

def jamendo_album_url(url)
  id = url[/album\/(\d+)/, 1]
  pl_url = "http://api.jamendo.com/get2/stream/track/m3u/?album_id=#{id}&order=numalbum_asc"
  open(pl_url).read.sub(/^#EXTM3U$/, '')
end

FileUtils.mkdir_p ROOT_FOLDER
playlist = open("#{Dir.tmpdir}/playlist.m3u", "w")
doc = Nokogiri.parse(open('http://www.reddit.com/r/listentothis/new.rss?sort=new'))
names = []

playlist.puts "#EXTM3U"
doc.search('rss channel item').each { |item|
  content = item.at('description').content
  d = Nokogiri::HTML(CGI.unescape(content))
  d.search('a').each {|a|
    next if not a.content == '[link]'
    url = URI.escape(a['href'])
    title = item.at('title').content
    name = item.at('guid').content.split('/').last
    names << name

    begin
      if url =~ /\.mp3$/
        playlist.puts "#EXTINF:-1,#{title}"
        playlist.puts url
      elsif url =~ /youtube.com/
        playlist.puts youtube_url(title, name, url)
      elsif url =~ /jamendo.com.*album/
        playlist.puts jamendo_album_url(url)
      elsif url =~ /last\.?fm/
        playlist.puts lastfm_url(title, name, url)
      end
    rescue OpenURI::HTTPError
      next
    end
  }
}

playlist.close
FileUtils.mv "#{Dir.tmpdir}/playlist.m3u", "#{ROOT_FOLDER}/playlist.m3u"

# Clean folder
Dir.glob("#{ROOT_FOLDER}/*.mp3").each { |file|
  name = File.basename(file, '.mp3')
  if not names.include? name
    FileUtils.rm file ,:force => true
  end
}


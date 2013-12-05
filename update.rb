require "rubygems"

require 'yaml'

gem 'typhoeus', '=0.6.6'
require "typhoeus"

def update_tmz
	puts "fetching TMZ feed..."
	response = Typhoeus.get("http://www.tmz.com/videos")
	html = response.body
	full_episodes = html[/FULL\sEPISODES(.*)tmz-tv-full-episodes/m, 1]
	raw_scan = full_episodes.scan(/"videoUrl":\s*"(.*\.mp4)"/)
	video_urls = raw_scan.map do |v| 
		video_url = v[0].gsub(/\\/, '')
		date = video_url[/(201\d-\d\d\/\d\d)/, 1]
		{'title' => date, 'link' => video_url}
	end
	
	File.open("_data/tmzfull.yml", "w+") do |f|
		f.write(video_urls.to_yaml)
	end
end
	
def update_cbs
	puts "fetching CBS feed..."
	
	response = Typhoeus.get("http://www.cbsnews.com/60-minutes/full-episodes/")
	html = response.body
	
	raw_scan = html.scan(/<a class\s*=\s*"main" href\s*=\s*"(\/videos\/.*)" title="(.*)">/)
	video_urls = raw_scan.map do |raw|
		entry = {}
		
		title = raw[1]
		link = raw[0]
		puts "  #{title}"
		puts "    #{link}"
		r = Typhoeus.get("http://www.cbsnews.com/#{link}")
		
		h = r.body
		
		raw = h.scan(/(media\\\/201\d\\\/\d\d\\\/\d\d\\\/(\d+\\\/)?60_\d\d\d\d_FULL_796\.mp4)/i)
		mp4_link = raw[0].is_a?(Array) ? raw[0][0] : raw[0]
		if mp4_link
			mp4_link.gsub!(/796/, '1296')
			mp4_link.gsub!(/\\/, '')
		
			{'title' => title, 'link' => mp4_link}
		else
			nil
		end
	end.compact	
	
	File.open("_data/sixtymin.yml", "w+") do |f|
		f.write(video_urls.to_yaml)
	end
end

update_tmz
#update_cbs
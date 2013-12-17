require "rubygems"

require 'yaml'

gem 'typhoeus', '=0.6.6'
require "typhoeus"

SIXTY_MIN_FILE = "_data/sixtymin.yml"

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
    title = raw[1]
    link = raw[0]
    puts "  #{title}"
    puts "    #{link}"
    r = Typhoeus.get("http://www.cbsnews.com/#{link}")

    h = r.body

    raw = h.scan(/(media\\\/201\d\\\/\d\d\\\/\d\d\\\/(\d+\\\/)?60_(\d\d\d\d)_FULL_796\.mp4)/i)
    matches = raw[0].is_a?(Array) ? raw[0] : raw

    if matches.empty?
      puts "    No mp4 link found for: #{title}"
    else
      mp4_link = matches[0]
      raw_date = matches[2]

      formatted_date = raw_date.insert(2, '/')

      if mp4_link
        mp4_link.gsub!(/796/, '1296')
        mp4_link.gsub!(/\\/, '')

        {'title' => title, 'link' => mp4_link, 'date' => formatted_date}
      else
        nil
      end
    end
  end.compact

  puts "Merging previous episodes..."
  previous_episodes = YAML.load_file(SIXTY_MIN_FILE)
  previous_episodes ||= []
  previous_episodes.each do |previous_episode|
    if video_urls.index(previous_episode)
      puts "Discarding duplicate episode: #{previous_episode['title']}"
    else
      video_urls << previous_episode
    end
  end
  File.open(SIXTY_MIN_FILE, "w+") do |f|
    f.write(video_urls.to_yaml)
  end
end

#update_tmz
update_cbs

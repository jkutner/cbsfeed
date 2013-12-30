require "rubygems"
require "bundler/setup"
require 'pry'
require 'yaml'
require 'time'
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

def cbs_link_pattern(show_key, date_digits, size)
 /(media(\\\/mpx)?\\\/201\d\\\/\d\d\\\/\d\d\\\/(\d+\\\/)?#{show_key}_(#{date_digits})_FULL_(NEW_)?#{size}\.mp4)/i
end

def fetch_cbs_matches(html, show_key, date_digits, size)
  raw = html.scan(cbs_link_pattern(show_key, date_digits, size))
  raw[0].is_a?(Array) ? raw[0] : raw
end

def scrape_cbs_url(url, show_key, output_file, extra_re='') 
  response = Typhoeus.get(url)
  html = response.body

  raw_scan = html.scan(/href\s*=\s*"(\/videos\/.*)"#{extra_re}/)
  seen = []
  video_urls = raw_scan.map do |raw|
    link = raw[0]
    if seen.index(link)
      nil
    else
      seen << link
    
      mr = link.match(/(\d+-\d+)-/)
      if mr 
        title = mr[1]
        date_digits = Time.parse("#{Time.now.year}-#{title}").strftime("%m%d")
      else
        title = raw.size > 2 ? raw[2] : "Unknown Episode"
        date_digits = '\d\d\d\d'
      end
      
      puts "  #{title}"
      puts "    #{link}"
      r = Typhoeus.get("http://www.cbsnews.com/#{link}")

      h = r.body

      matches = fetch_cbs_matches(h, show_key, date_digits, '(796|740|240)')

      if matches.empty?
        puts "    No mp4 link found for: #{title}"
      else
        mp4_link = matches[0]
        raw_date = matches[3]

        year = Time.now.year
        video_date = Time.parse("#{year}/#{raw_date.insert(2, '/')}")

        if mp4_link
          links = ['240', '740', '796', '1296'].map do |size|
            mp4_link.gsub!(/240/, size)
            mp4_link.gsub!(/740/, size)
            mp4_link.gsub!(/796/, size)
            mp4_link.gsub!(/\\/, '')
            mp4_link.dup
          end

          {'title' => title, 'links' => {
            'mp4_240' => links[0],
            'mp4_740' => links[1],
            'mp4_796' => links[2],
            'mp4_1296' => links[3]}, 
          'date' => video_date}
        else
          nil
        end
      end
    end
  end.compact.sort{|a,b| b['date'] <=> a['date'] }

  puts "Merging previous episodes..."
  previous_episodes = YAML.load_file(output_file)
  previous_episodes ||= []
  previous_episodes.each do |previous_episode|
    if video_urls.index(previous_episode)
      puts "Discarding duplicate episode: #{previous_episode['title']}"
    else
      video_urls << previous_episode
    end
  end
  File.open(output_file, "w+") do |f|
    f.write(video_urls[0..6].to_yaml)
  end
end

def update_60min
  puts "fetching 60Minutes feed..."
  scrape_cbs_url("http://www.cbsnews.com/60-minutes/full-episodes/", "60", "_data/sixtymin.yml", ' (title="(.*)")')
end

def update_evening_news
  puts "fetching EveningNews feed..."
  scrape_cbs_url("http://www.cbsnews.com/evening-news/full-episodes/", "EN", "_data/evening_news.yml")
end

#update_tmz
update_60min
update_evening_news

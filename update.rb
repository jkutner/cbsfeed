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

class CbsParser
  attr_reader :show_key

  def initialize(show_key)
    @show_key = show_key
  end

  def link_pattern(date_digits, size)
   /(media(\\\/mpx)?\\\/201\d\\\/\d\d\\\/\d\d\\\/(\d+\\\/)?#{show_key}_(#{date_digits})(1\d)?_FULL\d*_?(NEW_)?(FIX_)?#{size}\.mp4)/i
  end

  def fetch_matches(html, date_digits, size)
    raw = html.scan(link_pattern(date_digits, size))
    raw[0].is_a?(Array) ? raw[0] : raw
  end

  def massage_link_by_sizes(size, raw_link)
    link = raw_link.dup
    link.gsub!(/240/, size)
    link.gsub!(/740/, size)
    link.gsub!(/796/, size)
    link.gsub!(/\\/, '')
    link
  end

  def with_title_and_date_digits(raw, link)
    match_result = link.match(/(\d+-\d+)-/)
    if match_result
      title = match_result[1]
      date_digits = Time.parse("#{Time.now.year}-#{title}").strftime("%m%d")
    else
      title = raw.size > 2 ? raw[2] : "Unknown Episode"
      date_digits = '\d\d\d\d'
    end
    yield title, date_digits
  end

  def fetch_link_html(link)
    yield Typhoeus.get("http://www.cbsnews.com/#{link}").body
  end

  def with_size_links(html, title, date_digits)
    matches = fetch_matches(html, date_digits, '(796|740|240)')
    if matches.empty?
      puts "    No mp4 link found for: #{title}"
    else
      mp4_link = matches[0]
      raw_date = matches[3]
      if mp4_link
        links = %w(240 740 796 1296).map do |size|
          massage_link_by_sizes(size, mp4_link)
        end
        yield links, Time.parse("#{Time.now.year}/#{raw_date.insert(2, '/')}")
      end
    end
  end

  def extract_video_urls(raw, seen)
    link = raw[0]
    unless seen.index(link)
      with_title_and_date_digits(raw, link) do |title, date_digits|
        puts "  #{title}"
        puts "    #{link}"
        fetch_link_html(link) do |html|
          with_size_links(html, title, date_digits) do |links, video_date|
            return {
                'title' => title,
                'links' => {
                    'mp4_240' => links[0],
                    'mp4_740' => links[1],
                    'mp4_796' => links[2],
                    'mp4_1296' => links[3]},
                'date' => video_date}
          end
        end
      end
    end
  end

  def scrape_cbs_url(url, output_file, extra_re='')
    html = Typhoeus.get(url).body

    raw_scan = html.scan(/href\s*=\s*"(\/videos\/.*)"#{extra_re}/)

    video_urls = sort_according_to_today(raw_scan.inject([]) do |urls, raw|
      urls + [extract_video_urls(raw, urls)]
    end.compact)

    puts "Merging previous episodes..."
    (YAML.load_file(output_file) || []).each do |previous_episode|
      if video_urls.index(previous_episode)
        puts "Discarding duplicate episode: #{previous_episode['title']}"
      else
        video_urls << previous_episode
      end
    end
    File.open(output_file, "w+") do |f|
      f.write(video_urls[0..5].to_yaml)
    end
  end

  def sort_according_to_today(list)
    puts 'Sorting list of urls by date, according to today...'
    new_list = []
    now = Time.now

    until list.empty?
      best = list.inject do |best, i|
        if best.nil?
          i
        else
          diff = now - i['date']
          best_diff = now - best['date']
          diff > 0 and diff < best_diff ? i : best
        end
      end
      new_list << best
      list.delete(best)
    end
    new_list
  end
end

def update_60min
  puts "fetching 60Minutes feed..."
  CbsParser.new('60').scrape_cbs_url("http://www.cbsnews.com/60-minutes/full-episodes/", "_data/sixtymin.yml", ' (title="(.*)")')
end

def update_evening_news
  puts "fetching EveningNews feed..."
  CbsParser.new('EN').scrape_cbs_url("http://www.cbsnews.com/evening-news/full-episodes/", "_data/evening_news.yml")
end

#update_tmz
#update_60min
update_evening_news

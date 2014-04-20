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

class CbsEpisode
  attr :raw, :link

  def initialize(raw, link)
    @raw = raw
    @link = link
  end

  def fetch_html
    yield Typhoeus.get("http://www.cbsnews.com/#{@link}").body
  end
end

class CbsEveningNewsEpisode < CbsEpisode
  def title
    unless @title
      match_result = link.match(/(\d+-\d+)-/)
      if match_result
        month_and_day = match_result[1].split('-')
        @title = "#{format('%02d', month_and_day[0])}-#{format('%02d', month_and_day[1])}"
      else
        @title = '00-00'
      end
    end
    @title
  end

  def date_digits
    @date_digits ||= time.strftime("%m%d")
  end

  def time(raw_date=nil)
    @time ||= Time.parse("#{Time.now.year}-#{title}")
  rescue ArgumentError
    @time ||= raw_date || Time.now
  end
end

class CbsSixtyMinEpisode < CbsEpisode
  def title
    raw.size > 2 ? raw[2] : "Unknown Episode"
  end

  def date_digits
    '\d\d\d\d'
  end

  def time(raw_date=Time.now)
    raw_date
  end
end

class CbsParser
  attr_reader :show_key

  def initialize(show_key)
    @show_key = show_key
  end

  def link_pattern(date_digits, size)
    /(media(\\\/mpx)?\\\/201\d\\\/\d\d\\\/\d\d\\\/(\d+\\\/)?#{show_key}_(#{link_pattern_date(date_digits)})_FULL\d*_?(NEW_)?(v2_)?(FIX_)?(EBlockFix_)?#{size}\.mp4)/i
  end

  def link_pattern_date(date_digits)
    %r{#{date_digits[0..1]}\d{2}?#{date_digits[-2..-1]}\d{2}?}i
  end

  def fetch_matches(html, episode, size)
    raw = html.scan(link_pattern(episode.date_digits, size))
    matches = raw[0].is_a?(Array) ? raw[0] : raw

    if matches.empty?
      puts "    No mp4 link found for: #{episode.title}"
    else
      mp4_link = matches[0]
      raw_date = matches[3]
      yield mp4_link, raw_date if mp4_link
    end
  end

  def massage_link_by_sizes(size, raw_link)
    link = raw_link.dup
    link.gsub!(/240/, size)
    link.gsub!(/740/, size)
    link.gsub!(/796/, size)
    link.gsub!(/\\/, '')
    link
  end

  def create_episode(raw, link)
    if show_key == 'EN'
      yield CbsEveningNewsEpisode.new(raw, link)
    else
      yield CbsSixtyMinEpisode.new(raw, link)
    end
  end

  def with_size_links(html, episode)
    fetch_matches(html, episode, '(796|740|240)') do |mp4_link, raw_date|
      links = %w(240 740 796 1296).map do |size|
        massage_link_by_sizes(size, mp4_link)
      end
      yield links, episode.time(raw_date)
    end
  end

  def extract_video_urls(raw, seen)
    link = raw[0]
    unless seen.index(link)
      create_episode(raw, link) do |episode|
        puts "  #{episode.title}"
        puts "    #{link}"
        episode.fetch_html do |html|
          with_size_links(html, episode) do |links, video_date|
            return {
                'title' => episode.title,
                'links' => {
                  'orig' => link,
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
      video_url = extract_video_urls(raw, urls)
      video_urls = [video_url]
      pruned_urls = urls.compact
      pruned_urls.each do |u|
        if video_url.nil? or (u['title'] == video_url['title'] and u['links']['mp4_1296'] == video_url['links']['mp4_1296'])
          video_urls.pop
        end
      end
      pruned_urls + video_urls
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
      f.write(video_urls.take(6).to_yaml)
    end
  end

  def sort_according_to_today(list)
    puts 'Sorting list of urls by date, according to today...'
    new_list = []
    now = Time.now

    until list.empty?
      cur_best = list.inject do |best, i|
        if best.nil?
          i
        else
          diff = now - i['date']
          best_diff = now - best['date']
          diff > 0 and diff < best_diff ? i : best
        end
      end
      new_list << cur_best
      list.delete(cur_best)
    end
    new_list
  rescue
    list
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

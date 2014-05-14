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
      if match_result = link.match(/(\d{1,2}-\d{1,2})-/)
        month_and_day = match_result[1].split('-')
        @title = "#{format('%02d', month_and_day[0])}-#{format('%02d', month_and_day[1])}"
      elsif match_result = link.match(/(\d{2,4})-/)
        dd = match_result[1]
        if dd.size == 2
          @title = "0#{dd[0]}-0#{dd[1]}"
        elsif dd.size == 4
          @title = "#{dd[0..1]}-#{dd[2..3]}"
        else
          @title = "0#{dd[0]}-#{dd[1..2]}"
        end
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
    /(media(\\\/mpx)?\\\/201\d\\\/\d\d\\\/\d\d\\\/(\d{5,15}\\\/)?#{show_key}_?#{link_pattern_date}_FULL_#{link_pattern_date}.{0,20}_#{size}\.mp4)/i
  end

  def link_pattern_date
    %r{\d{0,6}_?}
  end

  def ipad_link_pattern
    %r{ipad-streaming.{50,100}#{show_key}_?\d{0,6}_Full_.{3,20}.m3u8}i
  end

  def fetch_matches(html, episode, size)
    raw = html.scan(link_pattern(episode.date_digits, size))
    matches = raw[0].is_a?(Array) ? raw[0] : raw

    ipad_match = html.scan(ipad_link_pattern)
    ipad_link = ipad_match.empty? ? "" : ipad_match[0]

    puts matches.empty? ?
      "    No mp4 link found for: #{episode.title}" :
      "    #{matches[0]}"
    puts ipad_link == "" ?
      "    No ipad link found for: #{episode.title}" :
      "    #{ipad_link}"

    mp4_link = matches[0] || ""
    yield mp4_link, ipad_link
  end

  def massage_link_by_sizes(size, raw_link)
    link = raw_link.dup
    link.gsub!(/240/, size)
    link.gsub!(/740/, size)
    link.gsub!(/796/, size)
    massage_link(link)
    link
  end

  def massage_link(raw_link)
    (raw_link.split('"')[0] || "").gsub(/\\/, '')
  end

  def create_episode(raw, link)
    if show_key == 'EN'
      yield CbsEveningNewsEpisode.new(raw, link)
    else
      yield CbsSixtyMinEpisode.new(raw, link)
    end
  end

  def with_size_links(html, episode)
    fetch_matches(html, episode, '(796|740|240)') do |mp4_link, ipad_link|
      links = %w(240 740 796 1296).map do |size|
        massage_link_by_sizes(size, mp4_link)
      end
      links << massage_link(ipad_link)
      yield links
    end
  end

  def extract_video_urls(raw, seen)
    link = massage_link(raw[0])
    unless seen.index(link)
      create_episode(raw, link) do |episode|
        puts "  #{episode.title}"
        puts "    #{link}"
        episode.fetch_html do |html|
          with_size_links(html, episode) do |links|
            return {
                'title' => episode.title,
                'links' => {
                  'orig' => link,
                  'ipad' => links[4],
                  'mp4_240' => links[0],
                  'mp4_740' => links[1],
                  'mp4_796' => links[2],
                  'mp4_1296' => links[3]},
                'date' => episode.title}
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
      f.write(video_urls.take(show_key == "60" ? 10 : 6).to_yaml)
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

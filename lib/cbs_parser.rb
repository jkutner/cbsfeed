
class CbsParser
  attr_reader :show_key

  def initialize(show_key)
    @show_key = show_key
  end

  def link_pattern(date_digits, size)
    /(media(\\\/mpx)?\\\/201\d\\\/\d\d\\\/\d\d\\\/(\d{5,15}\\\/)?#{show_key}_?#{link_pattern_date}_FULL#{link_pattern_date}.{0,20}_#{size}\.mp4)/i
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

    raw_scan = html.scan(/href\s*=\s*"(\/videos\/\d.*)"#{extra_re}/)

    video_urls = raw_scan.inject([]) do |urls, raw|
      video_url = extract_video_urls(raw, urls)
      video_urls = [video_url]
      pruned_urls = urls.compact
      pruned_urls.each do |u|
        if video_url.nil? or (u['title'] == video_url['title'] and u['links']['mp4_1296'] == video_url['links']['mp4_1296'])
          video_urls.pop
        end
      end
      pruned_urls + video_urls
    end.compact.sort {|x,y|  Date.strptime(y['date'], "%m-%d") <=>  Date.strptime(x['date'], "%m-%d") }

    puts "Merging previous episodes..."
    (YAML.load_file(output_file) || []).each do |previous_episode|
      if video_urls.index(previous_episode)
        puts "Discarding duplicate episode: #{previous_episode['title']}"
      else
        video_urls << previous_episode
      end
    end
    File.open(output_file, "w+") do |f|
      f.write(video_urls.take(8).to_yaml)
    end
  end
end

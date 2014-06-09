class CbsEpisode
  attr :raw, :link

  def initialize(raw, link)
    @raw = raw
    @link = link
  end

  def fetch_html
    r = Typhoeus.get("http://www.cbsnews.com/#{@link}")
    if r.success?
      yield r.body
    else
      puts "    page returned #{r.code}"
    end
  end
end

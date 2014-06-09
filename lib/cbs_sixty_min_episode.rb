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

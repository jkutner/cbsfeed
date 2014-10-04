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
          if dd[1].to_i == 0
            @title = "#{dd[0..1]}-0#{dd[2]}"
          else
            @title = "0#{dd[0]}-#{dd[1..2]}"
          end
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

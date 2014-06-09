require "rubygems"
require "bundler/setup"
require 'pry'
require 'yaml'
require 'time'
require "typhoeus"

require './lib/cbs_episode.rb'
require './lib/cbs_evening_news_episode.rb'
require './lib/cbs_sixty_min_episode.rb'
require './lib/cbs_parser.rb'

def update_60min
  puts "fetching 60Minutes feed..."
  CbsParser.new('60').scrape_cbs_url("http://www.cbsnews.com/60-minutes/full-episodes/", "_data/sixtymin.yml", ' (title="(.*)")')
end

def update_evening_news
  puts "fetching EveningNews feed..."
  CbsParser.new('EN').scrape_cbs_url("http://www.cbsnews.com/evening-news/full-episodes/", "_data/evening_news.yml")
end

update_60min
update_evening_news

require 'json'
require 'open-uri'
require 'bundler'
Bundler.require

class String
  def string_between_markers marker1, marker2
    self[/#{Regexp.escape(marker1)}(.*?)#{Regexp.escape(marker2)}/m, 1]
  end

  def titleize
    split(/(\W)/).map(&:capitalize).join
  end

  def underscore
    self.gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr("-", "_").
    downcase
  end
end

class DZScraper
  def states
    %w(AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MO MT NE NV NJ NM NY NC ND OH OK OR PA PR RI SC SD TN TX UT VT VA WA WV WI).sort
  end

  def countries
    %w(AR BE BR BG CA CN CR HR CZ DK FI FR DE GR GT IN IE IL IT JP KE LV MX MA NA PY PL PT RO RU RS ES CH TH AE).sort
  end

  def state_page_url(state)
    "http://www.uspa.org/Drop-Zone-Locator/region/#{state}"
  end

  def country_page_url(country)
    "http://www.uspa.org/Drop-Zone-Locator/country/#{country}"
  end

  def location_url(location)
    "http://www.uspa.org/Drop-Zone-Locator?location=#{location}"
  end

  def parse_state_country(file_name, abbrev, folder)
    # Open the file
    page = parse_file(file_name)
    # Get the links to the different dropzones in the state:
    dz_ids = page.css('a').select{|alink| alink.text.chomp == "View Details"}.map{|l| l[:href].split("=").last }
    dz_ids.each do |loc_id|
      dz_file_name = "local_files/#{folder}/#{abbrev}/#{loc_id}.html"
      unless File.file?(dz_file_name)
        url = location_url(loc_id)
        agent.get(url).save(dz_file_name)
      end

      page = parse_file(dz_file_name)
    end
  end

  def agent
    @_agent ||= Mechanize.new { |agent|
      agent.user_agent_alias = 'Mac Safari'
    }
  end

  def initialize
    dropzones = []

    # Start with States
    states.each do |abbrev|
      file_name = "local_files/usa/#{abbrev}.html"
      unless File.file?(file_name)
        url = state_page_url(abbrev)
        agent.get(url).save(file_name)
      end

      parse_state_country(file_name, abbrev, 'usa')
    end

    # Start with States
    countries.each do |abbrev|
      file_name = "local_files/international/#{abbrev}.html"
      unless File.file?(file_name)
        url = country_page_url(abbrev)
        agent.get(url).save(file_name)
      end
      parse_state_country(file_name, abbrev,'international')
    end


    # Get the continents
    # a.get('http://www.dropzone.com/dropzone') do |page|
    #
    #   # Loop over each continent and get the countries
    #   page.search(".lightblueBox.sidecontent dt a").each do |continent|
    #     continent_name = continent.text.chomp.strip
    #     ap "Got #{continent_name}"
    #
    #     # Get countries
    #     a.get(continent[:href]) do |continent_page|
    #
    #       continent_page.search('#catlisting dt').reject{|listing| listing.text.include?("(0)") }.each do |country|
    #         country_name = country.search('a').text.chomp.strip
    #         ap " - #{country_name}"
    #
    #         # Get states or dropzones
    #         a.get(country.search('a')[:href]) do |country_page|
    #           binding.pry
    #           abort
    #           ap country_page
    #           dztable = country_page.search('.ftablecol a')
    #
    #           if dztable.nil?
    #             ap "#{country_name} has states."
    #           else
    #             ap "#{country_name} does not have states."
    #
    #             #Get the individual dropzones for this country
    #             get_dz_info(dztable)
    #
    #           end
    #
    #           # if country_page.search('.ftable')
    #           # country_page.search('.ftable ')
    #         end
    #       end
    #     end
    #   end
      # search_result = page.form_with(:id => 'gbqf') do |search|
      #   search.q = 'Hello world'
      # end.submit

      # search_result.links.each do |link|
      #   puts link.text
      # end
    # end


    # get_continents
  end

  def parse_file(file_name)
    Nokogiri::HTML(open(file_name))
  end

  # def get_dz_info(table)
  #   ap table
  #   ap table.search('a')
  #   abort
  #   table.search('a').reject{|link| link[:href].include?('review') }.each do |dz_link|
  #     ap dz_link
  #     abort
  #   end
  # end

  # def get_continents
    # page = parsed_page('http://www.dropzone.com/dropzone/')

    # @continents = {}
    # page.css('.lightblueBox.sidecontent dt a').each do |c|
    #   @continents[c.text.chomp.strip] = {
    #     url: c[:href]
    #   }
    # end

    # @continents.each do |continent, value|
    #   @continents[continent][:countries] = get_countries(value[:url])
    # end

    # ap @continents
  # end

  # def get_countries(continent_url)
  #   page = parsed_page(continent_url)
  #   countries = {}
  #   page.css('#catlisting dt').reject{|listing| listing.text.include?("(0)") }.each do |c|
  #     a = c.css('a')
  #     country_name = a.text.chomp.strip
  #     url = a
  #     ap country_name
  #     ap url.attribute('href')
  #     # countries[href.text.chomp.strip] = {
  #     #   url: href[:href]
  #     # }
  #   end
  #   countries
  # end

  def parsed_page(url)
    html = open(URI.parse(url), "User-Agent" => "Mozilla/5.0 (compatible; MSIE 10.0; Macintosh; Intel Mac OS X 10_7_3; Trident/6.0)")
    Nokogiri::HTML(html)
  end
end

dzs = DZScraper.new

# File.open("../dropzones-new.geojson","w") do |f|
#   # f.write(dzs.scrape_local.to_json)
#   f.write(dzs.scrape_online.to_json)
# end

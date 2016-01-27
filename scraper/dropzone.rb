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
  def initialize
    cache_files_locally

    pretty = true
    result = scrape

    File.open("../dropzones-new.geojson","w") do |f|
      f.write(pretty ? JSON.pretty_generate(result) : result.to_json)
    end
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
    end
  end

  def agent
    @_agent ||= Mechanize.new { |agent|
      agent.user_agent_alias = 'Mac Safari'
    }
  end

  def cache_files_locally
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
  end

  def parse_file(file_name)
    Nokogiri::HTML(open(file_name))
  end

  def skip_anchors
    @_skip_anchors ||= [1179, 1149, 1185, 1189, 1173]
  end

  def scrape
    dzs = {
      type: 'FeatureCollection',
      features: []
    }
    all_files.map do |lf|
      # puts "Scraping #{lf}"
      html = open(lf)
      page = Nokogiri::HTML(html)

      parsed = parse(page, lf)

      dzs[:features] << parsed unless skip_anchors.include?(parsed[:properties][:anchor].to_i)
    end
    dzs
  end

  def parse(page, file_name)
    dz_data = {
      type: 'Feature',
      properties: {},
      geometry: {
        type: 'Point',
        coordinates: []
      }
    }

    dz_data[:properties][:anchor] = file_name.split("/").last.split(".").first
    dz_data[:properties][:name] = page.css('div.panel.panel-primary.dropzone > div.panel-heading > div > div > div.col-sm-8 > h3').text.chomp.strip

    # Get additional details about the DZ
    dz_data[:properties].merge!(details(page))

    # Grab the lat and lng
    dz_data[:geometry][:coordinates] = parse_lat_lng(dz_data[:properties].delete(:latlong))


    dz_data
  end

  def details(page)
    rows = page.css('div.panel.panel-primary.dropzone > div.panel-body > div.col-sm-12.col-md-5')

    detail = {}
    rows.search('dt').each do |node|
      key = parse_detail_key(node.text)
      detail[key] = parse_detail_value(node.next_element.text, key)
    end
    detail
  end

  def parse_detail_key(key)
    new_key = key.downcase.strip.chomp.gsub(":", "").gsub("/", "").gsub(" ", "_").to_sym

    case new_key
    when :additional_information
      :description
    else
      new_key
    end
  end

  def parse_detail_value(value, key)
    new_value = value.gsub("\t", "").gsub("\"\"", "\"").gsub("\n\n", "\n").strip.chomp

    case key
    when :aircraft
      new_value.split(", ")
    when :location
      new_value.split("\n")
    when :description
      if value.downcase == "none listed"
        ""
      else
        new_value
      end
    else
      new_value
    end
  end

  def parse_lat_lng(ll)
    ll.split(" : ")
  end

  def usa_files
    Dir["local_files/usa/*/*.html"]
  end

  def international_files
    Dir["local_files/international/*/*.html"]
  end

  def all_files
    usa_files + international_files
  end

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
end

dzs = DZScraper.new

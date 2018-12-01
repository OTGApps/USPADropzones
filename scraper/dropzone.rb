# require 'json'
require 'open-uri'
require 'bundler'
Bundler.require
require './string'
require './states'

require 'csv'

class DZScraper
  def initialize
    cache_files_locally

    pretty = true
    result = scrape

    # File.open("../../Dropzones/resources/dropzones.geojson", "w") do |f|
    File.open("../dropzones.geojson","w") do |f|
      f.write(pretty ? JSON.pretty_generate(result) : result.to_json)
    end
  end

  def cache_files_locally
    # Get the main dz locator page:
    file_name = "local_files/000_all.html"
    unless File.file?(file_name)
      puts "Writing file to: " + file_name
      agent.get("https://uspa.org/dzlocator").save(file_name)
    end

    # Extract all the places
    lines = []
    File.open(file_name).each do |line|
      lines << line.strip if line.strip.start_with?('markers.push') || line.strip.start_with?('infoWindowContent.push')
    end

    # Parse the places
    places = {}
    lines.each_with_index do |l, index|
      next if index.odd?

      account = lines[index+1].scan(/<([^>]*)>/).find{|a| a.first.include?('accountnumber')}.first
      if account
        account_number = account.split('=').last

        # Now get the name and lat/long
        data = l.gsub('markers.push([', '').gsub(']);', '')
        parsed_data = CSV.parse(data, :converters=> lambda {|f| f ? f.strip : nil}, :quote_char => "'").first
        places[account_number] = {
          name: parsed_data[0],
          latitude: parsed_data[1],
          longitude: parsed_data[2],
         }
      end
    end

    # Now that we have a list of the places and their lat/long, lets get their
    # details.

    places.keys.each do |place_account|
      file_name = "local_files/dropzone/#{place_account}.html"
      unless File.file?(file_name)
        puts "Writing file to: " + file_name
        agent.get(location_url(place_account)).save(file_name)
      end
    end

  end

  def skip_anchors
    @_skip_anchors ||= [
      196509, # Military Only Laurinburg-Maxton
      260335, # Military Only
      206689, # Complete Parachute Solutions Tactical Training Facility
      260335, # Military Freefall Solutions Inc.
      261413, # Naval Postgraduate School Foundation Skydiving Club
      269216, # University at Buffalo Skydiving Club
    ]
  end

  def scrape
    dzs = {
      type: 'FeatureCollection',
      features: []
    }
    all_files.map do |lf|
      anchor = lf.split("/").last.split(".").first.to_i

      if skip_anchors.include?(anchor)
        puts "SKIPPING #{lf}"
        next
      end

      puts "Scraping #{lf}"
      html = open(lf)
      page = Nokogiri::HTML(html)
      data_we_care_about = page.css('.mx-product-details-template .col-sm-10').first

      parsed = parse(data_we_care_about, anchor)

      # These two aren't in the data_we_care_about variable so we have to get it outside that code block.
      parsed[:properties][:training] = page.css('#dnn_ctr1586_ContentPane').css('p').last.parent.parent.parent.parent.text.split('##LOC[Cancel]##').last.strip.split("\r\n")
      parsed[:properties][:services] = page.css('#dnn_ctr1585_ModuleContent').css('p').last.parent.parent.parent.parent.text.split('##LOC[Cancel]##').last.strip.split("\r\n")

      # Sort by key
      parsed[:properties] = parsed[:properties].sort.to_h

      dzs[:features] << parsed #unless skip_anchors.include?(parsed[:properties][:anchor].to_i)
    end
    dzs[:features] = dzs[:features].sort_by{|f| f[:properties][:name]}
    pp dzs
    dzs
  end

  def parse(page, anchor)
    dz_data = {
      type: 'Feature',
      properties: {},
      geometry: {
        type: 'Point',
        coordinates: []
      }
    }

    dz_data[:properties][:anchor] = anchor
    dz_data[:properties][:name] = page.css('h2').first.text.chomp.strip
    pp 'name: ' + dz_data[:properties][:name]

    # Grab the lat and lng
    dz_data[:geometry][:coordinates] = parse_lat_lng(page).reverse

    dz_data[:properties][:website] = page.css('.fa-external-link').first.next_element.text
    dz_data[:properties][:phone] = page.css('.fa-phone').first.next_element.text.chomp.strip
    dz_data[:properties][:email] = page.css('.fa-envelope').first.next_element.text.chomp.strip
    dz_data[:properties][:aircraft] = parse_aircraft_string(page.css('.fa-plane').first.next_sibling.text.gsub(/[[:space:]]/, ' ').strip)
    dz_data[:properties][:description] = page.css('hr').first.next_element.text.chomp.strip
    dz_data[:properties][:location] = parse_location_array(page)

    dz_data
  end

  def parse_location_array(page)
    children = page.css('p').children
    children.shift
    first_i = children.find_index { |e| e.name == 'i' }
    location_array = children[0..first_i].search('~ br').map{|br| br.next.text.strip}.reject(&:empty?)
    location_array.map{|l| l.strip.gsub(/[[:space:]]/, ' ').gsub(/\s+/, ' ') }
  end

  def parse_aircraft_string(aircraft)
    new_value = aircraft.split(" and/or ").join(", ")
    new_value.split(", ").map do |a|
      new_a = a.split("--").first.chomp(" ").chomp(",")
      new_a = new_a.gsub("1-", "1 ")
      new_a = new_a.gsub("1Cessna", "1 Cessna")

      # Fix Aircraft Names
      new_a = new_a.gsub(/C-([0-9]{3})/, 'Cessna \1')
        .gsub("1 208", "1 Cessna 208")
        .gsub("P-750", "PAC 750")
        .gsub(" (varies)", "")
        .gsub("Cessna Caravan 208", "Cessna 208")
        .gsub("Skyvan", "SkyVan")
        .gsub("Supervan", "SuperVan")
        .gsub("R44", "Robinson 44")
        .gsub("850HP ", "")
        .gsub("50HP ", "")
        .gsub("Caravan SuperVan", "SuperVan")
        .gsub("SMG92-", "SMG-92 ")
        .gsub("c-182", "Cessna 182")
        .gsub("C 208", "Cessna 208")
        .gsub("C 172", "Cessna 172")
        .gsub("C-", "Cessna ")
        .gsub("Cessna Caravan", "Cessna 208 Caravan")
        .gsub("Cessna Grand Caravan", "Cessna 208B Grand Caravan")
        .gsub("Cessna SuperVan", "Cessna 208 SuperVan")
        .gsub("Grand Caravan", "Cessna 208B Grand Caravan")
        .gsub("SM-92T", "SM-92T Turbo Finist")
        .gsub("Super Cessna 182", "Cessna 182 (Super)")
        .gsub("Short Cessna 23 Sherpa", "Cessna 23 Sherpa (Short)")
        .gsub(" - PTG-A21 Turbo Prop", "")

      # Fix BlackHawk
      if new_a.downcase.match("blackhawk")
        new_a = new_a[0] + " Cessna 208 BlackHawk Grand Caravan"
      end

      # Fix 208B
      if new_a.end_with?("208B")
        new_a << " Grand Caravan"
      end

      # Fix Antonov An-2
      if new_a.downcase.end_with?("an-2") || new_a.downcase.end_with?("an2")
        new_a = new_a[0] + " Antonov An-2"
      end

      # Fix Super Caravan
      if new_a.downcase.end_with?("super caravan")
        new_a = new_a[0] + " Cessna 208 Super Caravan"
      end

      # Fix Caravan
      if new_a.downcase == "1 caravan"
        new_a = "1 Cessna 208 Caravan"
      end

      # Fix Turbine Porter
      if new_a.downcase.end_with?("turbine porter")
        new_a = new_a[0] + " Pilatus Porter"
      end

      # Fix Let L-410 Turbolet
      if new_a.match("L410") || new_a.match("Let 410") || new_a.match("L-410")
        new_a = new_a[0] + " Let L-410 Turbolet"
      end

      new_a = new_a.titleize if new_a.downcase.include?("beech") || new_a.downcase.include?("casa")
      new_a << " PA31" if new_a.end_with?("Navajo")
      new_a = "1 #{new_a}" unless new_a[0].is_i?

      # Fix issues with plurals
      new_a << "s" if new_a.start_with?("2") && !new_a.end_with?("s")
      new_a = new_a[0...-1] if new_a.start_with?("1") && new_a.end_with?("s")
      new_a.end_with?("Super") ? nil : new_a
    end.compact
  end

  def parse_lat_lng(page)
    links = page.css('a').map(&:values).flatten
    google_links =  links.select do |item|
      item.start_with?('https://www.google.com/maps/place/')
    end

    link = google_links.first
    coords = link.split('/@').last.split(',')[0..1]

    # fix a couple issues with the data.
    coords = coords.map{|ll| ll.gsub("30-", "30.").gsub("/", "") }

    coords.map(&:to_f)
  end

  def all_files
    Dir["local_files/dropzone/*.html"]
  end

  def location_url(location)
    "https://uspa.org/DZdetails?accountnumber=#{location}"
  end

  def agent
    @_agent ||= Mechanize.new { |agent|
      agent.user_agent_alias = 'Mac Safari'
    }
  end

end

dzs = DZScraper.new

class Location < ActiveRecord::Base
  class LocationHeader < Struct.new(:geocode_address, :precision, :distance); end
  
  acts_as_mappable
  belongs_to :type
  belongs_to :user
  serialize :contacts
  attr_protected :user

  def self.valid_options
    {
      :name => "LocationName",
      :type_id => Type.find(:first),
      :street_address => "Street Address",
      :city => "Anytown",
      :state => "US",
      :zip_code => "00000",
      :description => "description",
      :contacts => [],
      :hours => "",
      :url => 'http://domain.com',
      :is_aga => true
    }
  end

  def before_save
    clean_empty_contacts
    if self.slug.blank?
      self.slug == self.sluggify
    end
  end

  def user=(new_user)
    raise SecurityError.new("Must call change_user on objects already in the database") unless new_record?

    self.user_id = new_user.id
  end

  def user_id=(new_user_id)
    raise SecurityError.new("Must call change_user on objects already in the database") unless new_record?

    write_attribute(:user_id, new_user_id)
  end
    

  # Geocode the address represented by this location, storing the result in
  # lat and lng and returning the geocode object if it was successful, or nil
  # otherwise.
  def geocode
    geo = GeoKit::Geocoders::MultiGeocoder.geocode(geocode_address)
    if geo.success
      self.lat, self.lng = geo.lat, geo.lng
      return self
    else
      errors.add_to_base("Could not geocode address")
      return nil
    end
  end

  def geocode_address
    city_state_zip = ""

    unless city.blank? || state.blank?
      city_state_zip = city + ", " + state
    end

    unless zip_code.blank?
      city_state_zip += " " unless city_state_zip.blank?
      city_state_zip += zip_code
    end

    if city_state_zip.blank?
      errors.add_to_base("Must provide at least either city and state or zip code")
      return nil
    end

    if street_address.blank?
      geo_address = city_state_zip
    else
      geo_address = street_address + ", " + city_state_zip
    end

    return geo_address
  end

  def change_user(new_user, administrator)
    if(administrator.has_role?(:administrator))
      case new_user
      when User:
        write_attribute(:user, new_user)
      when Fixnum:
        write_attribute(:user_id, new_user)
      when String:
        write_attribute(:user_id, new_user.to_d)
      end
    else
      raise SecurityError.new("Only administrators may change owning user of a location")
    end
  end

  def precision
    unless street_address.blank?
      :address
    else
      :city
    end
  end
  
  # Returns the  sluggified string 
  def sluggify
    name = self.name.downcase.gsub(/[\W]/,'-').gsub(/[--]+/,'-').dasherize
    slug = Location.find_all_by_slug(name)
    if slug.size > 1
      return "#{name}-#{slug.size-1}"
    else
      return name
    end
  end

  private
  
  # Fires before saving a location and updates slug

  def clean_empty_contacts
    return if contacts.nil?

    contacts.delete_if do |contact|
      clean_blanks(contact)

      contact.blank? || has_only_blank_phones(contact)
    end

    self.contacts = nil if contacts.blank?
  end

  def has_only_blank_phones(contact)
    if contact.keys == [:phone]
      phone_array = contact[:phone]
      phone_array.delete_if do |phone|
        clean_blanks(phone)

        phone.keys == [:type]
      end

      return phone_array.blank?
    else
      return false
    end
  end

  def clean_blanks(hash)
    hash.delete_if{|key,value| value.blank?}
  end
end

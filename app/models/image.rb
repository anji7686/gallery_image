require 'crop_calc'

  class Image < ActiveRecord::Base
    belongs_to :root_image, inverse_of: :images
    has_many :gallery_images, inverse_of: :image, dependent: :destroy
    belongs_to :used_by, polymorphic: true

    #attr_accessible :has_roi, :roi_x, :roi_y, :roi_w, :roi_h, :crop_mode, :crop_fill_color, :roi, :fill_color,
    #                :alt_text, :title, :display_preference, :site_id, :status

    delegate :computed_roi, :computed_roi_h, :computed_roi_w, :computed_roi_x, :computed_roi_y, :has_computed_roi?,
             :height, :width, :name, :file_size, :base_name, :format, :full_image_path, :rm_img,
             :can_i_serve?, :fill_color_percentage,
             :license_restricted, :license_remarks, :is_license_cc, :license_cc_allow_modifications,
             :license_cc_allow_modifications_with_share_alike, :license_cc_allow_commercial, :image_credits, :to => :root_image

    SUPPORTED_CROP_MODES= %w(smart roi roih roiw full fill)

    before_update do |image|
      image.version += 1
    end

    after_destroy do |image|
      if Webdackimage.destroy_unused_images
        if image.root_image && image.root_image.unused?
          image.root_image.destroy
        end
      end
    end

    def image_id
      self.id
    end

    def image
      self
    end

    def image_path
      source_path(350,250)
    end

    def source_path(wid,heg)
      "/w-images/#{id}/#{version}/#{root_image.base_name}-#{wid}x#{heg}.#{root_image.format}"
    end

    def thumbnail
      begin
        self.get_image(80, 80, 'square')
      rescue
        nil
      end
    end

    def self.init_from_path(path, image_name, compute_roi)
      transaction do
        root_image= RootImage.init_from_path(path, image_name, compute_roi)
        image=root_image.use_image
        if compute_roi
          image.update_roi()
        end
        image
      end
    end

    def reuse
      copy= self.dup
      copy.save
      copy
    end

    def fresh_version
      root_image.use_image
    end

    def generate_preview(target_width, target_height, options={})
      options.reverse_merge!(:force => false)

      strategy = options[:variant] || 'default'

      case strategy
        when /^fill/
          a, color= strategy.split(/-/)
          img= crop_image_with_fill(target_width, target_height,
                                    {:color => color, :omit_border_threshold => options[:omit_border_threshold]})
        else # 'roi' or any other
          if !SUPPORTED_CROP_MODES.include?(strategy)
            strategy= "smart"
          end
          img= crop_image(strategy, target_width, target_height)
      end

      to_blob(img, options)
    end

    def scaled(target_width, target_height, options={})
      img= rm_img.collect {|frame| frame.resize(target_width, target_height)}
      to_blob(img, options)
    end

    def fit_within(target_width, target_height)
      width, height, border_x, border_y= CropCalc.fit_within(target_width, target_height, self.width, self.height)
      return [width, height]
    end

    def roi()
      {:x => roi_x, :y => roi_y, :w => roi_w, :h => roi_h}
    end

    def roi=(values)
      assign_attributes(
          :roi_x => values[:x] || values['x'],
          :roi_y => values[:y] || values['y'],
          :roi_w => values[:w] || values['w'],
          :roi_h => values[:h] || values['h'])
    end

    def update_roi
      if Webdackimage.use_sidekiq
        delay.update_roi_i
      else
        update_roi_i
      end
    end

    def computed_fill_color
      root_image.fill_color
    end

    private

    def crop_image_with_fill(target_width, target_height, options)
      options[:color] ||= fill_color
      options[:omit_border_threshold] ||= 2

      border_x, border_y= CropCalc.calculate_fill_borders(target_width, target_height, self.width, self.height,
                                                          options[:omit_border_threshold])

      rm_img.collect do |frame|
        frame.border(border_x, border_y, options[:color]).resize(target_width, target_height)
      end
    end

    def crop_image(strategy, target_width, target_height)
      if strategy == 'full' or !self.has_roi?
        t_roix, t_roiy, t_roi_width, t_roi_height= 0, 0, self.width, self.height
      else
        t_roix, t_roiy, t_roi_width, t_roi_height= roi_x, roi_y, roi_w, roi_h
      end

      offset_x, offset_y, crop_width, crop_height =
          CropCalc.calculate_crop_rect(strategy, target_width, target_height,
                                       self.width, self.height, t_roix, t_roiy, t_roi_width, t_roi_height)

      rm_img.collect do |frame|
        frame.excerpt(offset_x, offset_y, crop_width, crop_height).resize(target_width, target_height)
      end
    end

    def to_blob(img, options)
      img.to_blob {
        self.format= options[:format] if options[:format]
        self.quality= options[:quality] if options[:quality]
      }
    end

    def update_roi_i
      self.class.transaction do
        root_image.update_roi

        if !has_roi() then
          update_attributes(:has_roi => has_computed_roi?, :roi_x => computed_roi_x, :roi_y => computed_roi_y,
                            :roi_w => computed_roi_w, :roi_h => computed_roi_h)
        end
      end
    end

    def self.video_title_image(image_path, site_id, flag1=nil)
      media_detail_id = image_path.split("/")[2];
      image_name = image_path.split("/")[4];
      im = Magick::ImageList.new("#{Rails.root}/public/#{image_path}")
      i_width = im.columns
      i_height = im.rows
      r_image = Webdackimage::RootImage.create(name: image_name, width: i_width, height: i_height, uploaded_type_for_id: media_detail_id, uploaded_type_for: "MediaDetail", folder: "thumbs")
      image = Webdackimage::Image.create(root_image_id: r_image.id, purpose: "VideoThumbnails", used_by_type: "MediaDetail", used_by_id: media_detail_id)
      @media =  MediaDetail.find(media_detail_id)
      @media.image_id = image.id
      FileUtils.mkdir_p "#{Webdackimage.base_path}#{r_image.id[-3,3]}/#{r_image.id}", :mode => 0777
      dest_path = "#{Webdackimage.base_path}#{r_image.id[-3,3]}/#{r_image.id}/#{image_name}"
      source_path = "#{Rails.root}/public/#{image_path}"
      FileUtils.cp_r source_path, dest_path

      if @media.save
        return image
      else
        nil
      end
    end
  end

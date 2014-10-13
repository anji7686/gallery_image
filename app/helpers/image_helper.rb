module ImageHelper
    def image_version_url(image, width, height, variant=nil)
      _image_version_helper(false, image, width, height, variant)
    end

    def image_version_path(image, width, height, variant=nil)
      _image_version_helper(true, image, width, height, variant)
    end

    def _image_version_helper(only_path, image, width, height, variant=nil)
      image_format = image.format
      if image_format == "gif"
        options = {:only_path => only_path, :id => image.id, :name => image.base_name, :format => image_format,
                 :version => image.version, :dimension => "#{image.root_image.width}x#{image.root_image.height}" }
      else
        options = {:only_path => only_path, :id => image.id, :name => image.base_name, :format => image_format,
                 :version => image.version, :dimension => "#{width}x#{height}" }
      end
      # Use crop mode from image if it had one
      variant ||= image.crop_mode

      if variant
        options[:variant] = variant
      end

      webdackimage._image_version_url options
    end

    def scaled_image_url(image, options={})
      _scaled_image_helper(false, image, options)
    end

    def scaled_image_path(image, options={})
      _scaled_image_helper(true, image, options)
    end

    def _scaled_image_helper(only_path, image, options={})
      root_image= image.root_image

      if options[:max_width]
        if options[:max_height]
          width, height= image.fit_within(options[:max_width], options[:max_height])
        else
          width= options[:max_width]
          height= width * image.height / image.width
        end
      else
        if options[:max_height]
          height= options[:max_height]
          width=  height * image.width / image.height
        else
          width= image.width
          height= image.height
        end
      end

      options = {:only_path => only_path, :id => image.id, :name => root_image.base_name, :format => image.format,
                 :version => root_image.version, :dimension => "#{width}x#{height}" }

      webdackimage._scaled_image_url options
    end

    def root_image_url(image, variant=nil)
      _root_image_helper(false, image, variant)
    end

    def root_image_path(image, variant=nil)
      _root_image_helper(true, image, variant)
    end

    def _root_image_helper(only_path, image, variant=nil)
      root_image= image.root_image
      options = {:only_path => only_path, :id => image.id, :name => root_image.base_name,
                 :format => root_image.format, :version => root_image.version}
      if variant
        options[:variant] = variant
      end
      webdackimage._view_root_image_url options
    end
  end
end

if Webdackimage.support_legacy_api
  # Deepak: This whole code is full of hacks. These are written with a simple purpose to let the old view code
  # work it used to. The old helpers will generate Image links that are compatible with new approach.
  #
  # It works by extending the standard Rails helper image_tag. Remapping old method calls in Image, Gallery, and
  # GalleryImage, just ensure that :image, :width, :height reach the image_tag call, which in turn calls
  # image_version_path to generate the actual image path for the width and height.
  module Webdackimage
    # Make sure that these classes are loaded before extending those.
    Image
    Gallery
    GalleryImage

    class Image
      # <%=image_tag (article.image.resized_image(185,114).image_path,:alt=>"#{article.image.alt_tag}",:title=>"#{article.image.title}") if article.image %>
      # @article.image.display_preference !="hide_image"
      class SizedImageProxy < Struct.new(:image, :width, :height)
        def image_path
          self
        end
      end

      def resized_image(w, h)
        SizedImageProxy.new(self, w, h)
      end

      def get_image(w, h, orientation='none')
        SizedImageProxy.new(self, w, h)
      end

      def alt_tag
        self.alt_text
      end
    end

    class Gallery
      def image_sequence
        self
      end

      def image_properties
        gallery_images
      end
    end

    class GalleryImage
      # gallery_image.gallery_image_set("390x340").image_path
      def gallery_image_set(size)
        w, h= size.split('x').map(&:to_i)
        image.resized_image(w, h)
      end
    end

    module ImagesWpsHelper
      def image_tag(source, options={})
        if source.class == Webdackimage::Image::SizedImageProxy
          options[:src]= image_version_path(source.image, source.width, source.height)
          tag("img", options)
        else
          super
        end
      end
    end
end

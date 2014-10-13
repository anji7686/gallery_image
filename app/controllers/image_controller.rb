class ImageController < ApplicationController
	# For url generation for images and thumbnails

    layout 'image_application'
    include ImagesWpsHelper
    before_filter :page_property
    before_filter :check_image, :only => [:update_roi]

    def page_property
      @page_properties={ :selected_menu => 'image_list_menu', :menu_title => 'Image' }
    end

    # GET /images
    # GET /images.json
    def index
      if !params[:name].blank?
        @root_images = @all_root_images = RootImage.where("name like ? or name like ?", "%#{params[:name]}%","%#{params[:name].capitalize}%")
        case request.xhr?
          when 0
            render :partial => "search_image"
          when nil
            respond_to do |format|
              format.html # index.html.erb
              format.json { render json: @images }
            end
        end

      elsif params[:name].blank? && params[:empty_search] == "true"
        @root_images = RootImage.where(uploaded_type_for_id:params[:article_id]).order("updated_at desc") if params[:popup] == "true"
        @all_root_images = RootImage.order('updated_at desc')
        render :partial => "search_image", :layout => false if !params[:page]
        render "_search_image", :layout => 'image_application' if params[:page]
      elsif params[:popup] == "true"
        @popup = true
      else
        @all_root_images = RootImage.order('updated_at desc')
      end

      if !params[:name]
        respond_to do |format|
          format.html # index.html.erb
          format.json { render json: @images }
        end
      end
    end

    # GET /images/1
    # GET /images/1.json
    def show
      @image = Image.find(params[:id])

      respond_to do |format|
        format.html # show.html.erb
        format.json { render json: @image }
      end
    end

    def demo
      @image = Image.find(params[:id])

      respond_to do |format|
        format.html # demo.html.erb
        format.json { render json: @image }
      end
    end

    # GET /images/new
    # GET /images/new.json
    def new
      @image = Image.new

      respond_to do |format|
        format.html # new.html.erb
        format.json { render json: @image }
      end
    end

    # GET /images/new
    # GET /images/new.json
    def jq_uploader
      @image = Image.new

      respond_to do |format|
        format.html # new.html.erb
        format.json { render json: @image }
      end
    end


    # GET /images/1/edit
    def edit
      @image = Image.find(params[:id])
      @embedded = (params[:embedded] == 'true')
    end

    # POST /images
    # POST /images.json
    include ImagesHelper

    def upload

      @images= params[:image][:files].map do |image_params|
        Webdackimage::Utilities.init_image(image_params, params[:image][:attempt_roi_detection])
      end

        @root_images = @images.map do |image|
          if params[:image][:uploaded_type_for_id] && params[:image][:uploaded_type_for]
            image.root_image.update_attributes!(:uploaded_type_for_id=> params[:image][:uploaded_type_for_id], :uploaded_type_for => params[:image][:uploaded_type_for], :site_id => @site.id)
          else
            image.root_image.update_attributes!(:site_id => @site.id)
          end
          image.root_image
      end

      jq_fu_data= {}
      jq_fu_data[:files]= @root_images.map do |root_image|        {
            "name" => root_image.name,
            "size" => root_image.file_size,
            "url" => root_image_path(root_image.main_image),
            "thumbnail_url" => image_version_path(root_image.main_image, 50, 50),
            "html_fragment" => render_to_string(:partial => 'uploaded_image', :object => root_image)
        }
      end

      respond_to do |format|
        format.html {
          if params[:image][:mode] == "jq-upload"
            render json: jq_fu_data.to_json, content_type: 'text/html', layout: false
          else
            redirect_to action: "index" if !params[:popup]
            redirect_to action: "index", :popup => "true", :article_id => params[:image][:uploaded_type_for_id], :attach_type => params[:attach_type] if params[:popup]
          end
        }

        format.json { render json: jq_fu_data.to_json }
      end
    end

    # POST /images
    # POST /images.json
    def create
      upload()
    end

    # PUT /images/1
    # PUT /images/1.json
    def update
      if request.xhr?
        request.format= :json
        params[:format]= :json
      end

      @image = Image.find(params[:id])

      @image.assign_attributes(params.require(:image).permit(:has_roi, :crop_mode, :fill_color,
                                                             {:roi => [:x, :y, :x2, :y2, :w, :h]}))


      respond_to do |format|
        if @image.save
          if params[:popup] && params[:type] == "tiny_mce"
            format.html { redirect_to action: "index", :popup => "true", :article_id => params[:article_id], :type => "tiny_mce" }
          elsif params[:popup] && !params[:type]
            format.html { redirect_to action: "index", :article_id => params[:article_id], :popup => "true", :popup_crop => "true", :attach_type => params[:attach_type]}
          else
            format.html { redirect_to images_path, notice: 'Image was successfully updated.' }
          end
          format.json { render json: {message: 'Image was successfully updated.',
                                      image: {path: image_version_path(@image, 80, 80), id: @image.id}} }
        else
          format.html { render action: "edit" }
          format.json { render json: @image.errors, status: :unprocessable_entity }
        end
      end
    end

    # DELETE /images/1
    # DELETE /images/1.json
    def destroy

      @image = Image.find(params[:id])
      if @image
        @image.destroy
      end
      message= "Image removed successfully"
      if request.xhr?
        render json: {message: message}
      else
        redirect_to action: "show", notice: message
      end
    end

    def update_roi
      respond_to do |format|
        if @image.update_roi
          format.html { redirect_to @image, notice: 'Image ROI updation is scheduled.' }
          format.json { head :no_content }
        else
          format.html { redirect_to @image }
          format.json { render json: @image.errors, status: :unprocessable_entity }
        end
      end
    end

    def search_image
        if !params[:name].blank?
          @root_images = @all_root_images = RootImage.where("name like ? or name like ?", "%#{params[:name]}%","%#{params[:name].capitalize}%")
          case request.xhr?
            when 0
              render :partial => "search_image"
            when nil
              render :template => 'webdackimage/images/index.html.erb'
          end
        else
          redirect_to action: "index", :name=>"", :empty_search=>"true"
        end
    end
end

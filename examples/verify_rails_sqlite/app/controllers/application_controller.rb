class ApplicationController < ActionController::Base
  # CSRF protection is unnecessary in Tokra desktop apps.
  # Custom URL schemes (tokra://) cannot receive cross-site requests
  # from external websites, eliminating the attack vector.
  skip_forgery_protection

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end

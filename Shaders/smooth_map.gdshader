shader_type canvas_item;

// This controls how "sharp" the rounded corners are. 
// Higher values = sharper. Lower values = rounder/blurrier.
uniform float smoothing_factor : hint_range(0.5, 5.0) = 1.5;

void fragment() {
    // Get the size of a single pixel in UV space
    vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;
    
    // Scale UV by texture size to work in pixel coordinates
    vec2 pixel_uv = UV * tex_size;
    
    // Find the center of the current pixel and the fractional offset
    vec2 pixel_center = floor(pixel_uv + 0.5);
    vec2 pixel_fract = fract(pixel_uv + 0.5);
    
    // Apply smoothstep to round off the edges smoothly
    // The smoothing_factor prevents the edges from being completely hard
    pixel_fract = smoothstep(0.5 - (0.5 / smoothing_factor), 0.5 + (0.5 / smoothing_factor), pixel_fract);
    
    // Convert back to normalized UV space
    vec2 smooth_uv = (pixel_center + pixel_fract - 0.5) / tex_size;
    
    // Sample the texture using our smoothed coordinates
    COLOR = texture(TEXTURE, smooth_uv);
}
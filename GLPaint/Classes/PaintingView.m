/*
     File: PaintingView.m
 Abstract: The class responsible for the finger painting. The class wraps the 
 CAEAGLLayer from CoreAnimation into a convenient UIView subclass. The view 
 content is basically an EAGL surface you render your OpenGL scene into.
  Version: 1.11
 
 */

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>

#import "PaintingView.h"
#import "WebGet.h"
#import "ImageUtils.h"
#import "GridView.h"

// Constants
#define waitTime    2.0
#define numSections 196

//CLASS IMPLEMENTATIONS:

// A class extension to declare private methods
@interface PaintingView (private)

- (BOOL)createFramebuffer;
- (void)destroyFramebuffer;

@end

@implementation PaintingView

@synthesize  location;
@synthesize  previousLocation;
@synthesize  inkTouches;
@synthesize  grid;
@synthesize  gridView;
@synthesize  activeInternet;

// Implement this to override the default layer class (which is [CALayer class]).
// We do this so that our view will be backed by a layer that is capable of OpenGL ES rendering.
+ (Class) layerClass
{
	return [CAEAGLLayer class];
}

// The GL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:
- (id)initWithCoder:(NSCoder*)coder {
	
	CGImageRef		brushImage;
	CGContextRef	brushContext;
	GLubyte			*brushData;
	size_t			width, height;
    
    if ((self = [super initWithCoder:coder])) {
		CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
		
		eaglLayer.opaque = YES;
		// In this application, we want to retain the EAGLDrawable contents after a call to presentRenderbuffer.
		eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
										[NSNumber numberWithBool:YES], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
		
		context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
		
		if (!context || ![EAGLContext setCurrentContext:context]) {
			[self release];
			return nil;
		}
		
		brushImage = [UIImage imageNamed:@"ScrawlParticle.png"].CGImage;
		
		width = CGImageGetWidth(brushImage);
		height = CGImageGetHeight(brushImage);
		
		// Texture dimensions must be a power of 2. If you write an application that allows users to supply an image,
		// you'll want to add code that checks the dimensions and takes appropriate action if they are not a power of 2.
		
		if(brushImage) {
			// Allocate  memory needed for the bitmap context
			brushData = (GLubyte *) calloc(width * height * 4, sizeof(GLubyte));
			// Use  the bitmatp creation function provided by the Core Graphics framework. 
			brushContext = CGBitmapContextCreate(brushData, width, height, 8, width * 4, CGImageGetColorSpace(brushImage), kCGImageAlphaPremultipliedLast);
			// After you create the context, you can draw the  image to the context.
			CGContextDrawImage(brushContext, CGRectMake(0.0, 0.0, (CGFloat)width, (CGFloat)height), brushImage);
			CGContextRelease(brushContext);
			// Use OpenGL ES to generate a name for the texture.
			glGenTextures(1, &brushTexture);
			// Bind the texture name. 
			glBindTexture(GL_TEXTURE_2D, brushTexture);
			// Set the texture parameters to use a minifying filter and a linear filer (weighted average)
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
			// Specify a 2D texture image, providing the a pointer to the image data in memory
			glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, brushData);
			// Release  the image data; it's no longer needed
            free(brushData);
		}
		
		self.contentScaleFactor = 1.0;
	
		// Setup OpenGL states
		glMatrixMode(GL_PROJECTION);
		CGRect frame = self.bounds;
		CGFloat scale = self.contentScaleFactor;
        // Center the square view.
        dimension = [self maxDimensionForScreenSize:frame.size.width];
        offsetX = (frame.size.width - dimension) / 2;
        offset = (frame.size.height - dimension) / 2;
        NSLog(@"dimension: %d offsetX: %d offsetY: %d", dimension, offsetX, offset);
		glOrthof(offsetX, dimension * scale, offset, dimension * scale + offset, -1, 1);
        // glViewport is (x, y, width, height)
		glViewport(offsetX, offset, dimension * scale, dimension * scale);
		glMatrixMode(GL_MODELVIEW);
		
		glDisable(GL_DITHER);
		glEnable(GL_TEXTURE_2D);
		glEnableClientState(GL_VERTEX_ARRAY);
		
	    glEnable(GL_BLEND);
		// Set a blending function appropriate for premultiplied alpha pixel data
		glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
		
		glEnable(GL_POINT_SPRITE_OES);
		glTexEnvf(GL_POINT_SPRITE_OES, GL_COORD_REPLACE_OES, GL_TRUE);
		glPointSize(width / kBrushScale);
		
		// Make sure to start with a cleared buffer
		needsErase = YES;
		
        // Init inkTouches
        int numberOfPixels = dimension * dimension;
        self.inkTouches = [[NSMutableString alloc] initWithCapacity:numberOfPixels];
        for (int i=0; i<numberOfPixels; i++) {
            [self.inkTouches appendString:@"0"];
        }

        self.gridView = [[GridView alloc] initWithFrame:CGRectMake(offsetX, offset, dimension, dimension)];
        [self.gridView setSections:numSections];
        [self addSubview:self.gridView];
	}
    
	return self;
}

- (int) maxDimensionForScreenSize:(int)screenWidth
{
    // Want an evenly divided grid. On my phone, should return 308.
    int divSize = screenWidth / sqrt(numSections);
    return divSize * sqrt(numSections);
}

// If our view is resized, we'll be asked to layout subviews.
// This is the perfect opportunity to also update the framebuffer so that it is
// the same size as our display area.
-(void)layoutSubviews
{
	[EAGLContext setCurrentContext:context];
	[self destroyFramebuffer];
	[self createFramebuffer];
	
	// Clear the framebuffer the first time it is allocated
	if (needsErase) {
		[self erase];
		needsErase = NO;
	}
}

- (BOOL)createFramebuffer
{
	// Generate IDs for a framebuffer object and a color renderbuffer
	glGenFramebuffersOES(1, &viewFramebuffer);
	glGenRenderbuffersOES(1, &viewRenderbuffer);
	
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
	// This call associates the storage for the current render buffer with the EAGLDrawable (our CAEAGLLayer)
	// allowing us to draw into a buffer that will later be rendered to screen wherever the layer is (which corresponds with our view).
	[context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:(id<EAGLDrawable>)self.layer];
	glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, viewRenderbuffer);
	
	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);
	
	// For this sample, we also need a depth buffer, so we'll create and attach one via another renderbuffer.
	glGenRenderbuffersOES(1, &depthRenderbuffer);
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, depthRenderbuffer);
	glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_DEPTH_COMPONENT16_OES, backingWidth, backingHeight);
	glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER_OES, depthRenderbuffer);
	
	if(glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) != GL_FRAMEBUFFER_COMPLETE_OES)
	{
		NSLog(@"failed to make complete framebuffer object %x", glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES));
		return NO;
	}
	
	return YES;
}

// Clean up any buffers we have allocated.
- (void)destroyFramebuffer
{
	glDeleteFramebuffersOES(1, &viewFramebuffer);
	viewFramebuffer = 0;
	glDeleteRenderbuffersOES(1, &viewRenderbuffer);
	viewRenderbuffer = 0;
	
	if(depthRenderbuffer)
	{
		glDeleteRenderbuffersOES(1, &depthRenderbuffer);
		depthRenderbuffer = 0;
	}
}

// Releases resources when they are not longer needed.
- (void) dealloc
{
    [self.inkTouches release];
    [self.gridView release];
	if (brushTexture)
	{
		glDeleteTextures(1, &brushTexture);
		brushTexture = 0;
	}
	
	if([EAGLContext currentContext] == context)
	{
		[EAGLContext setCurrentContext:nil];
	}
	
	[context release];
	[super dealloc];
}

// Erases the screen
- (void) erase
{
	[EAGLContext setCurrentContext:context];
	
	// Clear the buffer
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
	glClearColor(0.0, 0.0, 0.0, 0.0);
	glClear(GL_COLOR_BUFFER_BIT);
	
	// Display the buffer
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
	[context presentRenderbuffer:GL_RENDERBUFFER_OES];
}

// Drawings a line onscreen based on where the user touches
- (void) renderLineFromPoint:(CGPoint)start toPoint:(CGPoint)end
{
	static GLfloat*		vertexBuffer = NULL;
	static NSUInteger	vertexMax = 64;
	NSUInteger			vertexCount = 0,
						count,
						i;
	
	[EAGLContext setCurrentContext:context];
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
	
	// Convert locations from Points to Pixels
	CGFloat scale = self.contentScaleFactor;
	start.x *= scale;
	start.y *= scale;
	end.x *= scale;
	end.y *= scale;
	
	// Allocate vertex array buffer
	if(vertexBuffer == NULL)
		vertexBuffer = malloc(vertexMax * 2 * sizeof(GLfloat));
	
	// Add points to the buffer so there are drawing points every X pixels
	count = MAX(ceilf(sqrtf((end.x - start.x) * (end.x - start.x) + (end.y - start.y) * (end.y - start.y)) / kBrushPixelStep), 1);
	for(i = 0; i < count; ++i) {
		if(vertexCount == vertexMax) {
			vertexMax = 2 * vertexMax;
			vertexBuffer = realloc(vertexBuffer, vertexMax * 2 * sizeof(GLfloat));
		}
		
		vertexBuffer[2 * vertexCount + 0] = start.x + (end.x - start.x) * ((GLfloat)i / (GLfloat)count);
		vertexBuffer[2 * vertexCount + 1] = start.y + (end.y - start.y) * ((GLfloat)i / (GLfloat)count);
		vertexCount += 1;
	}
	
	// Render the vertex array
	glVertexPointer(2, GL_FLOAT, 0, vertexBuffer);
	glDrawArrays(GL_POINTS, 0, vertexCount);
	
	// Display the buffer
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
	[context presentRenderbuffer:GL_RENDERBUFFER_OES];
}



- (void) toggleGridVisible
{
    [self.gridView setGridIsVisible:![gridView gridIsVisible]];
    // Will cause redraw.
    [self.gridView setNeedsDisplay];
}


// Handles the start of a touch
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    // If there's a timer set, cancel it.
    if (touchTimer != nil) {
        [touchTimer invalidate];
        [touchTimer release];
    }
    
	CGRect				bounds = [self bounds];
    UITouch*	touch = [[event touchesForView:self] anyObject];
	firstTouch = YES;
	// Convert touch point from UIView referential to OpenGL one (upside-down flip)
	location = [touch locationInView:self];
	location.y = bounds.size.height - location.y;
}

// Handles the continuation of a touch.
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{  
   	  
	CGRect				bounds = [self bounds];
	UITouch*			touch = [[event touchesForView:self] anyObject];
		
	// Convert touch point from UIView referential to OpenGL one (upside-down flip)
	if (firstTouch) {
		firstTouch = NO;
		previousLocation = [touch previousLocationInView:self];
		previousLocation.y = bounds.size.height - previousLocation.y;
	} else {
		location = [touch locationInView:self];
	    location.y = bounds.size.height - location.y;
		previousLocation = [touch previousLocationInView:self];
		previousLocation.y = bounds.size.height - previousLocation.y;
        
        // If the touch is within our square's bounds, remember it.
        int topBounds = offset + dimension;
        int rightBounds = offsetX + dimension;
        if (location.y < topBounds && location.y > offset && location.x > offsetX && location.x < rightBounds)
        {
            // For GL, 0,0 is bottom left, but for neural net it's top left. So flip y now.
            int realY = dimension - (location.y - offset);
            int realX = location.x - offsetX;
            int targetCharIndex = (realY * dimension) + realX;
            NSAssert(targetCharIndex < (dimension * dimension), @"Target character index larger than string");
            [self.inkTouches replaceCharactersInRange:NSMakeRange(targetCharIndex, 1) withString:@"1"];
        }
	}
    
	// Render the stroke
	[self renderLineFromPoint:previousLocation toPoint:location];
}

// Handles the end of a touch event when the touch is a tap.
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
	CGRect				bounds = [self bounds];
    UITouch*	touch = [[event touchesForView:self] anyObject];
	if (firstTouch) {
		firstTouch = NO;
		previousLocation = [touch previousLocationInView:self];
		previousLocation.y = bounds.size.height - previousLocation.y;
		[self renderLineFromPoint:previousLocation toPoint:location];
	}
    
    // Start a timer. If no touches in time, assume they're done and submit.
    touchTimer = [[NSTimer scheduledTimerWithTimeInterval:waitTime
                                                  target:self
                                                selector:@selector(submitDigit)
                                                userInfo:nil
                                                 repeats:NO] retain];
}

// Handles the end of a touch event.
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
	// If appropriate, add code necessary to save the state of the application.
	// This application is not saving state.
}

- (void)setBrushColorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
{
	// Set the brush color using premultiplied alpha values
	glColor4f(red	* kBrushOpacity,
			  green * kBrushOpacity,
			  blue	* kBrushOpacity,
			  kBrushOpacity);
}

// Get the response from WebGet and display it proudly. Then erase screen.
- (void)receiveData:(NSData *)data
{        
    // Hide our progress bar
    [aSpinner stopAnimating];
    [aSpinner release];
    
    NSError *e = nil;
    NSArray *jsonResponse = [NSJSONSerialization JSONObjectWithData: data options: NSJSONReadingMutableContainers error: &e];
    NSLog(@"response:\n%@", jsonResponse);
    int answer = [[[jsonResponse objectAtIndex:0] objectAtIndex:0] intValue];
    float answerCertainty = [[[jsonResponse objectAtIndex:0] objectAtIndex:1] floatValue];
    int secAnswer = [[[jsonResponse objectAtIndex:1] objectAtIndex:0] intValue];
    float secAnswerCertainty = [[[jsonResponse objectAtIndex:1] objectAtIndex:1] floatValue];
    float lastAnswerCertainty = [[[jsonResponse objectAtIndex:9] objectAtIndex:1] floatValue];
    NSString *message = [NSString stringWithFormat:@"%d  -  %.01f%% probability\n%d  -  %.01f%% probability", answer, (answerCertainty - lastAnswerCertainty) * 50, secAnswer, (secAnswerCertainty - lastAnswerCertainty) * 50];
    // Show the answers!
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"It looks like a %d", answer]
                                                     message:[NSString stringWithFormat:@"%@", message]
                                                    delegate:self
                                           cancelButtonTitle:@"Cool"
                                           otherButtonTitles:nil] autorelease];
    [alert show];
}

// Called by the system when UIAlertView is dismissed.
-(void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    // The shake message will dispatch to AppController and clear the screen.
    [[NSNotificationCenter defaultCenter] postNotificationName:@"shake" object:self];
}

- (void)submitDigit
{
    // After touching ends, submit the digit. If we have an internet connection.
    if (!self.activeInternet) {
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Whoops!"
                                                         message:[NSString stringWithFormat:@"No Internet."]
                                                        delegate:self
                                               cancelButtonTitle:@"Ok"
                                               otherButtonTitles:nil] autorelease];
        [alert show];
        return;
    }
    
    NSLog(@"Sending digit info");
    
    [touchTimer release];
    touchTimer = nil;
    
    // Make a progress bar, say we're going.
    aSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:
                UIActivityIndicatorViewStyleWhiteLarge];
    [self addSubview:aSpinner];
    [aSpinner setCenter:self.center];
    [aSpinner startAnimating];
    
    //Build the URL.
    ImageUtils *iutils = [[ImageUtils alloc] initWithSize:dimension
                                         numberOfSections:numSections
                                                pixelData:self.inkTouches];
    NSAssert([self.inkTouches length] == dimension * dimension,
             @"Have pixel data length %d, expected %d", [self.inkTouches length], dimension * dimension);
    NSString *destUrl = [iutils generateUrl];
    [iutils release];
    //Clear the touches list.
    [self.inkTouches replaceOccurrencesOfString:@"1"
                                     withString:@"0"
                                        options:NULL
                                          range:NSMakeRange(0, [self.inkTouches length])];
    // Don't know why this is necessary, but without it, after the 2nd drawing, the
    // string changes to immutable.
    self.inkTouches = [self.inkTouches mutableCopy];
    
    WebGet *wget = [[WebGet alloc] initWithUrl:destUrl
                                   callMeMaybe:self];
    // We can release wget, it will call us later maybe. At self.receiveData.
    [wget release];
}

@end

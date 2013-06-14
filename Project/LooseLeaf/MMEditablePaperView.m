//
//  MMEditablePaperView.m
//  LooseLeaf
//
//  Created by Adam Wulf on 5/24/13.
//  Copyright (c) 2013 Milestone Made, LLC. All rights reserved.
//

#import "MMEditablePaperView.h"
#import <QuartzCore/QuartzCore.h>
#import <JotUI/JotUI.h>
#import "NSThread+BlockAdditions.h"

@implementation MMEditablePaperView{
    NSUInteger lastSavedUndoHash;
}

- (id)initWithFrame:(CGRect)frame andUUID:(NSString*)_uuid{
    self = [super initWithFrame:frame andUUID:_uuid];
    if (self) {
        // create the cache view
        cachedImgView = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
        cachedImgView.frame = self.contentView.bounds;
        cachedImgView.contentMode = UIViewContentModeScaleAspectFill;
        cachedImgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        cachedImgView.clipsToBounds = YES;
        [self.contentView addSubview:cachedImgView];

        // create the drawable view
        drawableView = [[JotView alloc] initWithFrame:self.bounds];
        [self.contentView addSubview:drawableView];

        debug_NSLog(@"loading ink %@", [self inkPath]);
        
        if([[NSFileManager defaultManager] fileExistsAtPath:[self plistPath]]){
            [drawableView loadImage:[self inkPath] andState:[self plistPath]];
            cachedImgView.image = [UIImage imageWithContentsOfFile:[self thumbnailPath]];
        }else{
            [drawableView loadImage:nil andState:nil];
        }
        
        drawableView.delegate = self;

        // anchor the view to the top left,
        // so that when we scale down, the drawable view
        // stays in place
        drawableView.layer.anchorPoint = CGPointMake(0,0);
        drawableView.layer.position = CGPointMake(0,0);
        
        [[JotStylusManager sharedInstance] setPalmRejectorDelegate:drawableView];
        
        lastSavedUndoHash = [drawableView undoHash];
    }
    return self;
}


-(void) setFrame:(CGRect)frame{
    [super setFrame:frame];
    CGFloat _scale = frame.size.width / self.superview.frame.size.width;
    drawableView.transform = CGAffineTransformMakeScale(_scale, _scale);
}

#pragma mark - Public Methods

-(void) undo{
    [drawableView undo];
}

-(void) redo{
    [drawableView redo];
}

-(void) setEditable:(BOOL)isEditable{
    if(isEditable){
        cachedImgView.hidden = YES;
        drawableView.hidden = NO;
    }else{
        cachedImgView.hidden = NO;
        drawableView.hidden = YES;
    }
}


-(void) saveToDisk:(void(^)(void))onComplete{
    //
    // Sanity checks on directory structure
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* documentsPath = [paths objectAtIndex:0];
    NSString* pagesPath = [documentsPath stringByAppendingPathComponent:@"Pages"];
    if(![[NSFileManager defaultManager] fileExistsAtPath:pagesPath]){
        [[NSFileManager defaultManager] createDirectoryAtPath:pagesPath withIntermediateDirectories:NO attributes:nil error:nil];
    }
    
    // find out what our current undo state looks like.
    NSUInteger currentUndoHash = [drawableView undoHash];
    if(currentUndoHash != lastSavedUndoHash){
        // something has changed since the last time we saved,
        // so ask the JotView to save out the png of its data
        lastSavedUndoHash = currentUndoHash;
        debug_NSLog(@"saving page %@ with hash %ui", self.uuid, lastSavedUndoHash);
        
        [drawableView exportInkTo:[self inkPath]
                   andThumbnailTo:[self thumbnailPath]
                       andPlistTo:[self plistPath]
                       onComplete:^(UIImage* ink, UIImage* thumbnail, NSDictionary* state){
                           [NSThread performBlockOnMainThread:^{
                               cachedImgView.image = thumbnail;
                               onComplete();
                           }];
                       }];
    }else{
        // already saved, but don't need to write
        // anything new to disk
        onComplete();
    }
}

#pragma mark - JotViewDelegate

-(BOOL) willBeginStrokeWithTouch:(JotTouch*)touch{
    if(panGesture.state == UIGestureRecognizerStateBegan ||
       panGesture.state == UIGestureRecognizerStateChanged){
        if([panGesture containsTouch:touch.touch]){
            return NO;
        }
    }
    return [delegate willBeginStrokeWithTouch:touch];
}

-(void) willMoveStrokeWithTouch:(JotTouch*)touch{
    [delegate willMoveStrokeWithTouch:touch];
}

-(void) didEndStrokeWithTouch:(JotTouch*)touch{
    [delegate didEndStrokeWithTouch:touch];
}

-(void) didCancelStrokeWithTouch:(JotTouch*)touch{
    [delegate didCancelStrokeWithTouch:touch];
}

-(UIColor*) colorForTouch:(JotTouch *)touch{
    return [delegate colorForTouch:touch];
}

-(CGFloat) widthForTouch:(JotTouch*)touch{
    //
    // we divide by scale so that when the user is zoomed in,
    // their pen is always writing at the same visible scale
    //
    // this lets them write smaller text / detail when zoomed in
    return [delegate widthForTouch:touch] / self.scale;
}

-(CGFloat) smoothnessForTouch:(JotTouch *)touch{
    return [delegate smoothnessForTouch:touch];
}

-(CGFloat) rotationForSegment:(AbstractBezierPathElement *)segment fromPreviousSegment:(AbstractBezierPathElement *)previousSegment{
    return [delegate rotationForSegment:segment fromPreviousSegment:previousSegment];;
}




#pragma mark - File Paths

-(NSString*) pagesPath{
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* documentsPath = [paths objectAtIndex:0];
    NSString* pagesPath = [documentsPath stringByAppendingPathComponent:@"Pages"];
    
    if(![[NSFileManager defaultManager] fileExistsAtPath:pagesPath]){
        [[NSFileManager defaultManager] createDirectoryAtPath:pagesPath withIntermediateDirectories:NO attributes:nil error:nil];
    }
    return pagesPath;
}

-(NSString*) inkPath{
    return [[[self pagesPath] stringByAppendingPathComponent:self.uuid] stringByAppendingPathExtension:@"png"];;
}

-(NSString*) plistPath{
    return [[[self pagesPath] stringByAppendingPathComponent:self.uuid] stringByAppendingPathExtension:@"plist"];;
}

-(NSString*) thumbnailPath{
    return [[[self pagesPath] stringByAppendingPathComponent:[self.uuid stringByAppendingString:@".thumb"]] stringByAppendingPathExtension:@"png"];
}


@end

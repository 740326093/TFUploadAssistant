//
//  TFPHAssetFile.m
//  TFUploadAssistant
//
//  Created by Melvin on 3/23/16.
//  Copyright © 2016 TimeFace. All rights reserved.
//

#import "TFPHAssetFile.h"
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import "TFConfiguration.h"
enum {
    kAMASSETMETADATA_PENDINGREADS = 1,
    kAMASSETMETADATA_ALLFINISHED = 0
};

@interface TFPHAssetFile () {
    BOOL _hasGotInfo;
}

@property (nonatomic) PHAsset * phAsset;

@property (readonly) int64_t fileSize;

@property (readonly) int64_t fileModifyTime;

@property (nonatomic, strong) NSData *assetData;

@property (nonatomic, strong) NSURL *assetURL;

@end

@implementation TFPHAssetFile

- (instancetype)init:(PHAsset *)phAsset error:(NSError *__autoreleasing *)error
{
    if (self = [super init]) {
        NSDate *createTime = phAsset.creationDate;
        int64_t t = 0;
        if (createTime != nil) {
            t = [createTime timeIntervalSince1970];
        }
        _fileModifyTime = t;
        _phAsset = phAsset;
        [self getInfo];
        
    }
    return self;
}

- (NSData *)read:(long)offset size:(long)size
{
    NSRange subRange = NSMakeRange(offset, size);
    if (!self.assetData) {
        self.assetData = [self fetchDataFromAsset:self.phAsset];
    }
    NSData *subData = [self.assetData subdataWithRange:subRange];
    
    return subData;
}

- (NSData *)readAll {
    return [self read:0 size:(long)_fileSize];
}

- (void)close {
}

-(NSString *)path {
    return self.assetURL.path;
}

- (NSString *)fileExtension {
    NSString *fileExtension = @"jpg";
    NSString * filename = [self.phAsset valueForKey:@"filename"];
    if (filename.length) {
        fileExtension = [filename pathExtension];
    }
    return fileExtension;
}
- (int64_t)modifyTime {
    return _fileModifyTime;
}


- (NSString *)mimeType {
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                                                            (__bridge CFStringRef)self.fileExtension, NULL);
    CFStringRef MIMEType = UTTypeCopyPreferredTagWithClass (UTI, kUTTagClassMIMEType);
    CFRelease(UTI);
    
    NSString *mimeType = (__bridge NSString *)MIMEType;
    CFRelease(MIMEType);
    return mimeType;
}

- (int64_t)size {
    return _fileSize;
}

- (void)getInfo
{
    if (!_hasGotInfo) {
        _hasGotInfo = YES;
        
        if (PHAssetMediaTypeImage == self.phAsset.mediaType) {
            PHImageRequestOptions *request = [PHImageRequestOptions new];
            request.version = PHImageRequestOptionsVersionCurrent;
            request.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
            request.resizeMode = PHImageRequestOptionsResizeModeNone;
            request.synchronous = YES;
            
            [[PHImageManager defaultManager] requestImageDataForAsset:self.phAsset
                                                              options:request
                                                        resultHandler:^(NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *info) {
                                                            _fileSize = imageData.length;
                                                            _assetURL = [NSURL URLWithString:self.phAsset.localIdentifier];
                                                        }
             ];
        }
        else if (PHAssetMediaTypeVideo == self.phAsset.mediaType) {
            PHVideoRequestOptions *request = [PHVideoRequestOptions new];
            request.deliveryMode = PHVideoRequestOptionsDeliveryModeAutomatic;
            request.version = PHVideoRequestOptionsVersionCurrent;
            
            NSConditionLock* assetReadLock = [[NSConditionLock alloc] initWithCondition:kAMASSETMETADATA_PENDINGREADS];
            [[PHImageManager defaultManager] requestPlayerItemForVideo:self.phAsset options:request resultHandler:^(AVPlayerItem *playerItem, NSDictionary *info) {
                AVURLAsset *urlAsset = (AVURLAsset *)playerItem.asset;
                NSNumber *fileSize = nil;
                [urlAsset.URL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
                _fileSize = [fileSize unsignedLongLongValue];
                _assetURL = urlAsset.URL;
                
                [assetReadLock lock];
                [assetReadLock unlockWithCondition:kAMASSETMETADATA_ALLFINISHED];
            }];
            [assetReadLock lockWhenCondition:kAMASSETMETADATA_ALLFINISHED];
            [assetReadLock unlock];
            assetReadLock = nil;
        }
    }
    
}

- (NSData *)fetchDataFromAsset:(PHAsset *)asset
{
    __block NSData *tmpData = [NSData data];
    
    // Image
    if (asset.mediaType == PHAssetMediaTypeImage) {
        PHImageRequestOptions *request = [PHImageRequestOptions new];
        request.version = PHImageRequestOptionsVersionCurrent;
        request.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
        request.resizeMode = PHImageRequestOptionsResizeModeNone;
        request.synchronous = YES;
        
        [[PHImageManager defaultManager] requestImageDataForAsset:asset
                                                          options:request
                                                    resultHandler:
         ^(NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *info) {
             tmpData = [NSData dataWithData:imageData];
         }];
    }
    // Video
    else  {
        
        PHVideoRequestOptions *request = [PHVideoRequestOptions new];
        request.deliveryMode = PHVideoRequestOptionsDeliveryModeAutomatic;
        request.version = PHVideoRequestOptionsVersionCurrent;
        
        NSConditionLock *assetReadLock = [[NSConditionLock alloc] initWithCondition:kAMASSETMETADATA_PENDINGREADS];
        
        
        [[PHImageManager defaultManager] requestAVAssetForVideo:asset
                                                        options:request
                                                  resultHandler:
         ^(AVAsset* asset, AVAudioMix* audioMix, NSDictionary* info) {
             AVURLAsset *urlAsset = (AVURLAsset *)asset;
             NSData *videoData = [NSData dataWithContentsOfURL:urlAsset.URL];
             tmpData = [NSData dataWithData:videoData];
             
             [assetReadLock lock];
             [assetReadLock unlockWithCondition:kAMASSETMETADATA_ALLFINISHED];
         }];
        
        [assetReadLock lockWhenCondition:kAMASSETMETADATA_ALLFINISHED];
        [assetReadLock unlock];
        assetReadLock = nil;
    }
    
    return tmpData;
}

@end

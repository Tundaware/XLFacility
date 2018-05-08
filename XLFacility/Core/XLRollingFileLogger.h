/*
 Copyright (c) 2014, Pierre-Olivier Latour
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * The name of Pierre-Olivier Latour may not be used to endorse
 or promote products derived from this software without specific
 prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL PIERRE-OLIVIER LATOUR BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "XLLogger.h"

NS_ASSUME_NONNULL_BEGIN

/**
 *  The XLRollingFileLogger class writes logs records to a file with options
 *  for automatically rolling the log and limiting the number of total files.
 *
 *  @warning XLRollingFileLogger does not perform any buffering when writing to
 *  the file i.e. log records are written to disk immediately.
 */
@interface XLRollingFileLogger : XLLogger

/**
 *  Returns the directoryPath as specified when the logger was initialized
 *  The directoryPath is the directory that will contain the log files.
 */
@property(nonatomic, readonly, nonnull) NSString* directoryPath;

/**
 *  The maxFileSize is the maximum size any individual log file is allowed to
 *  become. Once this size is exceeded, a new file will be generated.
 */
@property(nonatomic) long long maxFileSize;

/**
 *  The maxNumberOfFiles is the maximum number of log files to keep.
 *  Once exceeded, the oldest file by creation date will be removed until the
 *  limit is no longer exceeded.
 */
@property(nonatomic) NSUInteger maxNumberOfFiles;

/**
 *  This method is a designated initializer for the class.
 *
 *  @param path - The directory to store log files in
 *  @param create - Create the directory if it doesn't exist
 */
- (instancetype)initWithDirectoryPath:(NSString* _Nonnull)path create:(BOOL)create;

/**
 *  Subclasses can override this to provide a custom filename format
 *  The default implementation uses the current [[NSDate date] timeIntervalSince1970]
 *  as the filename and '.log' as the extension.
 */
- (NSString *)generateNextLogFilename;

/**
 *  Subclasses can override this to provide custom logic regarding when to roll
 *  the log file.
 *
 *  @warning This will be called once per log record, the implementation should
 *  be as minimal and fast as possible.
 */
- (BOOL)shouldRoll;

@end

@interface XLRollingFileLoggerFileInfo : NSObject

@property (nonatomic, readonly, copy, nonnull) NSString *filePath;
@property (nonatomic, readonly, strong) NSDate *creationDate;
@property (nonatomic, readonly) long long size;

+(instancetype)fileInfoWithPath:(NSString * _Nonnull)path;

@end

NS_ASSUME_NONNULL_END

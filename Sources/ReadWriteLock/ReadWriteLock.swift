/*===============================================================================================================================================================================*
 *     PROJECT: ReadWriteLock
 *    FILENAME: ReadWriteLock.swift
 *         IDE: AppCode
 *      AUTHOR: Galen Rhodes
 *        DATE: 1/3/22
 *
 * Copyright © 2022. All rights reserved.
 *
 * Permission to use, copy, modify, and distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this
 * permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO
 * EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
 * AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *===============================================================================================================================================================================*/

import Foundation
import CoreFoundation
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

#if os(Windows)
    import WinSDK

    @usableFromInline typealias OSRWLock = UnsafeMutablePointer<SRWLOCK>
    @usableFromInline typealias OSThreadKey = DWORD
#elseif CYGWIN
    @usableFromInline typealias OSRWLock = UnsafeMutablePointer<pthread_rwlock_t?>
    @usableFromInline typealias OSThreadKey = pthread_key_t
#else
    @usableFromInline typealias OSRWLock = UnsafeMutablePointer<pthread_rwlock_t>
    @usableFromInline typealias OSThreadKey = pthread_key_t
#endif

/*==============================================================================================================*/
/// An implementation of a classic [Read/Write](https://en.wikipedia.org/wiki/Readers–writer_lock) lock.
/// 
/// NOTE: You should use caution with DispatchQueues. DispatchQueues reuse threads.
///
public class ReadWriteLock {
    //@f:0
    /*==========================================================================================================*/
    /// The values for the state of the lock for the current thread. Either `Read`, `Write`, or `None`.
    ///
    @usableFromInline enum RWState { case None, Read, Write }

    /*==========================================================================================================*/
    /// Holds the state of the lock for the current thread.
    ///
    @usableFromInline @ThreadLocal var rwState: RWState = .None
    /*==========================================================================================================*/
    /// The OS lock handle.
    ///
    @usableFromInline              var lock:    OSRWLock
    //@f:1

    /*==========================================================================================================*/
    /// Creates a Read/Write lock by calling the underlying OS libraries.
    ///
    public init() {
        lock = OSRWLock.allocate(capacity: 1)
        #if os(Windows)
            InitializeSRWLock(lock)
        #else
            guard pthread_rwlock_init(lock, nil) == 0 else { initializationError() }
        #endif
        rwState = .None
    }

    /*==========================================================================================================*/
    /// Deallocates the OS Read/Write lock and releases any allocated resources.
    ///
    deinit {
        #if !os(Windows)
            pthread_rwlock_destroy(lock)
        #endif
        lock.deallocate()
    }

    /*==========================================================================================================*/
    /// Displays a message that the current thread already owns a different lock than the one it's requesting and
    /// then terminates the application.
    /// 
    /// - Returns: Never
    ///
    @usableFromInline func wrongOwnershipError() -> Never {
        fatalError("Thread does not currently own the lock for \(!rwState).  It owns it for \(rwState).")
    }

    /*==========================================================================================================*/
    /// Displays a message that the current thread does not own any locks and then terminates the application.
    /// 
    /// - Returns: Never
    ///
    @usableFromInline func nonOwnershipError() -> Never {
        fatalError("Thread does not currently own the lock.")
    }

    /*==========================================================================================================*/
    /// Displays a message that the current thread already owns the lock that it's requesting and then terminates
    /// the application.
    /// 
    /// - Returns: Never
    ///
    @usableFromInline func alreadyOwnsError() -> Never {
        fatalError("Thread already owns the lock for \(rwState).")
    }

    /*==========================================================================================================*/
    /// Displays a message that an unknown error has occurred and then terminates the application.
    /// 
    /// - Returns: Never
    ///
    @usableFromInline func unknownError() -> Never {
        fatalError("Unknown Error.")
    }

    /*==========================================================================================================*/
    /// Displays a message that the Read/Write lock could not be initialized and then terminates the application.
    /// 
    /// - Returns: Never
    ///
    @usableFromInline func initializationError() -> Never {
        fatalError("Unable to initialize read/write lock.")
    }
}

extension ReadWriteLock {
    /*==========================================================================================================*/
    /// Unlocks a read lock.
    ///
    @inlinable func readUnlock() {
        guard rwState.isReading else { rwState.isWriting ? wrongOwnershipError() : nonOwnershipError() }
        #if os(Windows)
            ReleaseSRWLockShared(lock)
        #else
            pthread_rwlock_unlock(lock)
        #endif
        rwState = .None
    }

    /*==========================================================================================================*/
    /// Unlocks a write lock.
    ///
    @inlinable func writeUnlock() {
        guard rwState.isWriting else { rwState.isReading ? wrongOwnershipError() : nonOwnershipError() }
        #if os(Windows)
            ReleaseSRWLockExclusive(lock)
        #else
            pthread_rwlock_unlock(lock)
        #endif
        rwState = .None
    }

    /*==========================================================================================================*/
    /// Executes the given closure while holding the read lock. The read lock is acquired before the closure is
    /// executed and then automatically released when the closure completes or if an exception is thrown.
    /// 
    /// - Parameter body: The closure to execute while holding the read lock.
    /// - Returns: The value, if any, returned by the closure.
    /// - Throws: Any error thrown by the closure.
    ///
    @inlinable @discardableResult public func withReadLock<T>(_ body: () throws -> T) rethrows -> T {
        readLock()
        defer { readUnlock() }
        return try body()
    }

    /*==========================================================================================================*/
    /// Executes the given closure while holding the write lock. The write lock is acquired before the closure is
    /// executed and then automatically released when the closure completes or if an exception is thrown.
    /// 
    /// - Parameter body: The closure to execute while holding the write lock.
    /// - Returns: The value, if any, returned by the closure.
    /// - Throws: Any error thrown by the closure.
    ///
    @inlinable @discardableResult public func withWriteLock<T>(_ body: () throws -> T) rethrows -> T {
        writeLock()
        defer { writeUnlock() }
        return try body()
    }

    /*==========================================================================================================*/
    /// Tries to execute the given closure while holding the read lock. The read lock is acquired before the
    /// closure is executed and then automatically released when the closure completes or if an exception is
    /// thrown. If the read lock is not immediately available then the closure is never executed and this method
    /// returns `nil`.
    /// 
    /// - Parameter body: The closure to execute while holding the read lock.
    /// - Returns: The value, if any, returned by the closure or `nil` if the read lock could not be immediately
    ///            acquired.
    /// - Throws: Any error thrown by the closure.
    ///
    @inlinable @discardableResult public func tryWithReadLock<T>(_ body: () throws -> T) rethrows -> T? {
        guard tryReadLock() else { return nil }
        defer { readUnlock() }
        return try body()
    }

    /*==========================================================================================================*/
    /// Tries to execute the given closure while holding the write lock. The write lock is acquired before the
    /// closure is executed and then automatically released when the closure completes or if an exception is
    /// thrown. If the write lock is not immediately available then the closure is never executed and this method
    /// returns `nil`.
    /// 
    /// - Parameter body: The closure to execute while holding the write lock.
    /// - Returns: The value, if any, returned by the closure or `nil` if the write lock could not be immediately
    ///            acquired.
    /// - Throws: Any error thrown by the closure.
    ///
    @inlinable @discardableResult public func tryWithWriteLock<T>(_ body: () throws -> T) rethrows -> T? {
        guard tryWriteLock() else { return nil }
        defer { writeUnlock() }
        return try body()
    }

    /*==========================================================================================================*/
    /// Acquires the read lock.
    ///
    @inlinable public func readLock() {
        guard rwState == .None else { alreadyOwnsError() }
        #if os(Windows)
            AcquireSRWLockShared(lock)
        #else
            guard pthread_rwlock_rdlock(lock) == 0 else { unknownError() }
        #endif
        rwState = .Read
    }

    /*==========================================================================================================*/
    /// Attempts to acquire the read lock. If the read lock is currently being held by another thread then this
    /// method returns `false`. Otherwise the read lock is acquired by this thread and `true` is returned.
    /// 
    /// - Returns: `false` if another thread currently holds the read lock. Otherwise, `true`.
    ///
    @inlinable public func tryReadLock() -> Bool {
        guard rwState == .None else { alreadyOwnsError() }
        var success: Bool = false
        #if os(Windows)
            success = (TryAcquireSRWLockShared(lock) != 0)
        #else
            let r = pthread_rwlock_tryrdlock(lock)
            guard value(r, isOneOf: 0, EBUSY) else { unknownError() }
            success = (r == 0)
        #endif
        if success { rwState = .Read }
        return success
    }

    /*==========================================================================================================*/
    /// Acquires the write lock.
    ///
    @inlinable public func writeLock() {
        guard rwState == .None else { alreadyOwnsError() }
        #if os(Windows)
            AcquireSRWLockExclusive(lock)
        #else
            guard pthread_rwlock_wrlock(lock) == 0 else { unknownError() }
        #endif
        rwState = .Write
    }

    /*==========================================================================================================*/
    /// Attempts to acquire the write lock. If the write lock is currently being held by another thread then this
    /// method returns `false`. Otherwise the write lock is acquired by this thread and `true` is returned.
    /// 
    /// - Returns: `false` if another thread currently holds the write lock. Otherwise, `true`.
    ///
    @inlinable public func tryWriteLock() -> Bool {
        guard rwState == .None else { alreadyOwnsError() }
        var success: Bool = false
        #if os(Windows)
            success = (TryAcquireSRWLockExclusive(lock) != 0)
        #else
            let r = pthread_rwlock_tryrdlock(lock)
            guard value(r, isOneOf: 0, EBUSY) else { unknownError() }
            success = (r == 0)
        #endif
        if success { rwState = .Write }
        return success
    }

    /*==========================================================================================================*/
    /// Unlock the read or write lock being held by the current thread.
    ///
    @inlinable public func unlock() {
        switch rwState {
            case .Read:  readUnlock()
            case .Write: writeUnlock()
            default:     nonOwnershipError()
        }
    }
}

extension ReadWriteLock.RWState: CustomStringConvertible {
    @inlinable var description: String { isReading ? "reading" : (isWriting ? "writing" : "neither") }
    @inlinable var isReading:   Bool { self == .Read }
    @inlinable var isWriting:   Bool { self == .Write }

    /*==========================================================================================================*/
    /// Returns the state that is opposite of the one provided. If the state is `Read` then `Write` is returned.
    /// If the state is `Write` then `Read` is returned. If the state is `None` then `None` is returned.
    /// 
    /// - Parameter s: The state.
    /// - Returns: The opposite state.
    ///
    @inlinable static prefix func ! (s: Self) -> Self { s.isReading ? .Write : (s.isWriting ? .Read : .None) }
}

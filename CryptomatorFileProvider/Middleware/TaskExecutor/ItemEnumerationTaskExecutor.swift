//
//  ItemEnumerationTaskExecutor.swift
//  CryptomatorFileProvider
//
//  Created by Philipp Schmid on 18.05.21.
//  Copyright © 2021 Skymatic GmbH. All rights reserved.
//

import CocoaLumberjackSwift
import CryptomatorCloudAccessCore
import FileProvider
import Foundation
import GRDB
import Promises

class ItemEnumerationTaskExecutor: WorkflowMiddleware {
	private var next: AnyWorkflowMiddleware<FileProviderItemList>?

	func setNext(_ next: AnyWorkflowMiddleware<FileProviderItemList>) {
		self.next = next
	}

	func getNext() throws -> AnyWorkflowMiddleware<FileProviderItemList> {
		guard let nextMiddleware = next else {
			throw WorkflowMiddlewareError.missingMiddleware
		}
		return nextMiddleware
	}

	private let itemMetadataManager: ItemMetadataManager
	private let cachedFileManager: CachedFileManager
	private let uploadTaskManager: UploadTaskManager
	private let reparentTaskManager: ReparentTaskManager
	private let deletionTaskManager: DeletionTaskManager
	private let deleteItemHelper: DeleteItemHelper
	private let provider: CloudProvider

	init(provider: CloudProvider, itemMetadataManager: ItemMetadataManager, cachedFileManager: CachedFileManager, uploadTaskManager: UploadTaskManager, reparentTaskManager: ReparentTaskManager, deletionTaskManager: DeletionTaskManager, deleteItemHelper: DeleteItemHelper) {
		self.provider = provider
		self.itemMetadataManager = itemMetadataManager
		self.cachedFileManager = cachedFileManager
		self.uploadTaskManager = uploadTaskManager
		self.reparentTaskManager = reparentTaskManager
		self.deletionTaskManager = deletionTaskManager
		self.deleteItemHelper = deleteItemHelper
	}

	func execute(task: CloudTask) -> Promise<FileProviderItemList> {
		guard let enumerationTask = task as? ItemEnumerationTask else {
			return Promise(WorkflowMiddlewareError.incompatibleCloudTask)
		}
		let itemMetadata = enumerationTask.itemMetadata
		switch itemMetadata.type {
		case .folder:
			return fetchItemList(folderMetadata: itemMetadata, pageToken: enumerationTask.pageToken)
		case .file:
			return fetchItemMetadata(fileMetadata: itemMetadata)
		default:
			DDLogError("Unable to enumerate items on metadata type: \(itemMetadata.type)")
			return Promise(NSFileProviderError(.noSuchItem))
		}
	}

	func fetchItemList(folderMetadata: ItemMetadata, pageToken: String?) -> Promise<FileProviderItemList> {
		return provider.fetchItemList(forFolderAt: folderMetadata.cloudPath, withPageToken: pageToken).then { itemList -> FileProviderItemList in
			if pageToken == nil {
				try self.itemMetadataManager.flagAllItemsAsMaybeOutdated(withParentID: folderMetadata.id!)
			}

			var metadataList = [ItemMetadata]()
			for cloudItem in itemList.items {
				let fileProviderItemMetadata = ItemEnumerationTaskExecutor.createItemMetadata(for: cloudItem, withParentId: folderMetadata.id!)
				metadataList.append(fileProviderItemMetadata)
			}
			metadataList = try self.filterOutWaitingReparentTasks(parentId: folderMetadata.id!, for: metadataList)
			metadataList = try self.filterOutWaitingDeletionTasks(parentId: folderMetadata.id!, for: metadataList)
			try self.itemMetadataManager.cacheMetadata(metadataList)
			let reparentMetadata = try self.getReparentMetadata(for: folderMetadata.id!)
			metadataList.append(contentsOf: reparentMetadata)
			let placeholderMetadata = try self.itemMetadataManager.getPlaceholderMetadata(withParentID: folderMetadata.id!)
			metadataList.append(contentsOf: placeholderMetadata)
			let uploadTasks = try self.uploadTaskManager.getTaskRecords(for: metadataList)
			assert(metadataList.count == uploadTasks.count)
			let items = try metadataList.enumerated().map { index, metadata -> FileProviderItem in
				let localCachedFileInfo = try self.cachedFileManager.getLocalCachedFileInfo(for: metadata)
				let newestVersionLocallyCached = localCachedFileInfo?.isCurrentVersion(lastModifiedDateInCloud: metadata.lastModifiedDate) ?? false
				let localURL = localCachedFileInfo?.localURL
				return FileProviderItem(metadata: metadata, newestVersionLocallyCached: newestVersionLocallyCached, localURL: localURL, error: uploadTasks[index]?.failedWithError)
			}
			if let nextPageTokenData = itemList.nextPageToken?.data(using: .utf8) {
				return FileProviderItemList(items: items, nextPageToken: NSFileProviderPage(nextPageTokenData))
			}
			try self.cleanUpNoLongerInTheCloudExistingItems(insideParentId: folderMetadata.id!)
			return FileProviderItemList(items: items, nextPageToken: nil)
		}
	}

	func getReparentMetadata(for parentId: Int64) throws -> [ItemMetadata] {
		let reparentTasks = try reparentTaskManager.getTaskRecordsForItemsWhichAreSoon(in: parentId)
		let reparentMetadata = try itemMetadataManager.getCachedMetadata(forIDs: reparentTasks.map { $0.correspondingItem })
		return reparentMetadata
	}

	func filterOutWaitingReparentTasks(parentId: Int64, for itemMetadata: [ItemMetadata]) throws -> [ItemMetadata] {
		let runningReparentTasks = try reparentTaskManager.getTaskRecordsForItemsWhichWere(in: parentId)
		return itemMetadata.filter { element in
			!runningReparentTasks.contains { $0.sourceCloudPath == element.cloudPath }
		}
	}

	func filterOutWaitingDeletionTasks(parentId: Int64, for itemMetadata: [ItemMetadata]) throws -> [ItemMetadata] {
		let runningDeletionTasks = try deletionTaskManager.getTaskRecordsForItemsWhichWere(in: parentId)
		return itemMetadata.filter { element in
			!runningDeletionTasks.contains { $0.cloudPath == element.cloudPath }
		}
	}

	func fetchItemMetadata(fileMetadata: ItemMetadata) -> Promise<FileProviderItemList> {
		return provider.fetchItemMetadata(at: fileMetadata.cloudPath).then { cloudItem -> FileProviderItemList in
			let fileProviderItemMetadata = ItemEnumerationTaskExecutor.createItemMetadata(for: cloudItem, withParentId: fileMetadata.parentId)
			try self.itemMetadataManager.cacheMetadata(fileProviderItemMetadata)
			assert(fileProviderItemMetadata.id == fileMetadata.id)
			let localCachedFileInfo = try self.cachedFileManager.getLocalCachedFileInfo(for: fileProviderItemMetadata)
			let newestVersionLocallyCached = localCachedFileInfo?.isCurrentVersion(lastModifiedDateInCloud: fileProviderItemMetadata.lastModifiedDate) ?? false
			let localURL = localCachedFileInfo?.localURL
			let uploadTask = try self.uploadTaskManager.getTaskRecord(for: fileProviderItemMetadata)

			let item = FileProviderItem(metadata: fileProviderItemMetadata, newestVersionLocallyCached: newestVersionLocallyCached, localURL: localURL, error: uploadTask?.failedWithError)
			return FileProviderItemList(items: [item], nextPageToken: nil)
		}
	}

	func cleanUpNoLongerInTheCloudExistingItems(insideParentId parentId: Int64) throws {
		let outdatedItems = try itemMetadataManager.getMaybeOutdatedItems(withParentID: parentId)
		for outdatedItem in outdatedItems {
			try deleteItemHelper.removeItemFromCache(outdatedItem)
			try itemMetadataManager.removeItemMetadata(with: outdatedItem.id!)
		}
	}

	static func createItemMetadata(for item: CloudItemMetadata, withParentId parentId: Int64, isPlaceholderItem: Bool = false) -> ItemMetadata {
		ItemMetadata(name: item.name, type: item.itemType, size: item.size, parentId: parentId, lastModifiedDate: item.lastModifiedDate, statusCode: .isUploaded, cloudPath: item.cloudPath, isPlaceholderItem: isPlaceholderItem)
	}
}

//
//  ListViewModel.swift
//  Cryptomator
//
//  Created by Philipp Schmid on 08.01.21.
//  Copyright © 2021 Skymatic GmbH. All rights reserved.
//

import Combine
import CryptomatorCommonCore
import Foundation
import Promises
import UIKit

protocol ListViewModel {
	var headerTitle: String { get }
	var emptyListMessage: String { get }
	var removeAlert: ListViewModelAlertContent { get }
	func moveRow(at sourceIndex: Int, to destinationIndex: Int) throws
	func removeRow(at index: Int) throws
	func startListenForChanges() -> AnyPublisher<Result<[TableViewCellViewModel], Error>, Never>
}

struct ListViewModelAlertContent {
	let title: String
	let message: String
	let confirmButtonText: String
}

protocol VaultListViewModelProtocol: ListViewModel {
	func refreshVaultLockStates() -> Promise<Void>
    func updateSearchController(searchBarText: String?)
    func inSearchMode(_ searchController: UISearchController) -> Bool
    var filteredVaults: [VaultInfo] {get}
    var allVaults: [VaultInfo] { get }
    var onVaultsUpdated: (() -> Void)? { get set }
    
}

protocol AccountListViewModelProtocol: ListViewModel {
	var accounts: [AccountCellContent] { get }
	var accountInfos: [AccountInfo] { get }
	var title: String { get }
	var cloudProviderType: CloudProviderType { get }
}

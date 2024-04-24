//
//  VaultListViewController.swift
//  Cryptomator
//
//  Created by Philipp Schmid on 04.01.21.
//  Copyright © 2021 Skymatic GmbH. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import CryptomatorCommonCore
import Dependencies
import Foundation
import UIKit

class VaultListViewController: ListViewController<VaultCellViewModel> {
	weak var coordinator: MainCoordinator?

    private var viewModel: VaultListViewModelProtocol
	private var observer: NSObjectProtocol?
	@Dependency(\.fullVersionChecker) private var fullVersionChecker
    
    private var searchController = UISearchController(searchResultsController: nil)
    
    

	init(with viewModel: VaultListViewModelProtocol) {
		self.viewModel = viewModel
		super.init(viewModel: viewModel)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		title = "The Cryptomator"
        
        setupNavigationBar()
        setupSearchController()
        
        self.viewModel.onVaultsUpdated = { [weak self] in
            DispatchQueue.main.async {
                self?.tableView.reloadData()
            }
        }
        
		let settingsSymbol: UIImage?
		if #available(iOS 14, *) {
			settingsSymbol = UIImage(systemName: "gearshape")
		} else {
			settingsSymbol = UIImage(systemName: "gear")
		}
		let settingsButton = UIBarButtonItem(image: settingsSymbol, style: .plain, target: self, action: #selector(showSettings))
		navigationItem.leftBarButtonItem = settingsButton
		let addNewVaulButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addNewVault))
		navigationItem.rightBarButtonItem = addNewVaulButton

		observer = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
			self?.viewModel.refreshVaultLockStates().catch { error in
				DDLogError("Refresh vault lock states failed with error: \(error)")
			}
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		viewModel.refreshVaultLockStates().catch { error in
			DDLogError("Refresh vault lock states failed with error: \(error)")
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if CryptomatorUserDefaults.shared.showOnboardingAtStartup {
			coordinator?.showOnboarding()
		} else if fullVersionChecker.hasExpiredTrial, !CryptomatorUserDefaults.shared.showedTrialExpiredAtStartup {
			coordinator?.showTrialExpired()
		}
	}

	override func registerCells() {
		tableView.register(VaultCell.self, forCellReuseIdentifier: "VaultCell")
	}

//	override func configureDataSource() {
//		dataSource = EditableDataSource<Section, VaultCellViewModel>(tableView: tableView, cellProvider: { tableView, _, cellViewModel in
//			let cell = tableView.dequeueReusableCell(withIdentifier: "VaultCell") as? VaultCell
//			cell?.configure(with: cellViewModel)
//			return cell
//		})
//	}
    
    override func configureDataSource() {
        dataSource = EditableDataSource<Section, VaultCellViewModel>(tableView: tableView, cellProvider: { tableView, indexPath, cellViewModel in
            let inSearchMode = !self.searchController.searchBar.text!.isEmpty
            let vaults = inSearchMode ? self.viewModel.filteredVaults : self.viewModel.allVaults
            
            // Check if the index is within bounds
            guard indexPath.row < vaults.count else {
                 // Log error and return a dummy cell
                 NSLog("Attempted to access index \(indexPath.row) which is out of bounds for vaults count \(vaults.count)")
                 return UITableViewCell()
             }
            let vault = vaults.element(at: indexPath.row)
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "VaultCell", for: indexPath) as? VaultCell,
                  let vault = vault else {
                return UITableViewCell()  // Return an empty or configured "error" cell if preferred
            }
            cell.configure(with: vault as! VaultCellViewModel)
            return cell

        })
    }



	override func setEditing(_ editing: Bool, animated: Bool) {
		super.setEditing(editing, animated: animated)
		header.isEditing = editing
	}

	override func removeRow(at indexPath: IndexPath) throws {
		guard let vaultCellViewModel = dataSource?.itemIdentifier(for: indexPath) else {
			return
		}
		try super.removeRow(at: indexPath)
		coordinator?.removedVault(vaultCellViewModel.vault)
	}

	@objc func addNewVault() {
		setEditing(false, animated: true)
		coordinator?.addVault()
	}

	@objc func showSettings() {
		setEditing(false, animated: true)
		coordinator?.showSettings()
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		super.tableView(tableView, didSelectRowAt: indexPath)
		if let vaultCellViewModel = dataSource?.itemIdentifier(for: indexPath) {
			coordinator?.showVaultDetail(for: vaultCellViewModel.vault)
		}
	}
    
    
    
    // New: Setup and configure the search controller
    private func setupSearchController() {
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search Vaults"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    // Refactored: Setup navigation bar with dynamic button based on iOS version
    private func setupNavigationBar() {
        let settingsSymbol: UIImage?
        if #available(iOS 14, *) {
            settingsSymbol = UIImage(systemName: "gearshape")
        } else {
            settingsSymbol = UIImage(systemName: "gear")
        }
        let settingsButton = UIBarButtonItem(image: settingsSymbol, style: .plain, target: self, action: #selector(showSettings))
        navigationItem.leftBarButtonItem = settingsButton
        let addNewVaultButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addNewVault))
        navigationItem.rightBarButtonItem = addNewVaultButton
    }

    private func checkStartupConditions() {
        if CryptomatorUserDefaults.shared.showOnboardingAtStartup {
            coordinator?.showOnboarding()
        } else if fullVersionChecker.hasExpiredTrial, !CryptomatorUserDefaults.shared.showedTrialExpiredAtStartup {
            coordinator?.showTrialExpired()
        }
    }
}

// New: Extension to handle search results updating
extension VaultListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        print("DEBUG PRINT:", searchController.searchBar.text)
        self.viewModel.updateSearchController(searchBarText: searchController.searchBar.text ?? "")
        self.tableView.reloadData()
    }
}

extension Array {
    func element(at index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}


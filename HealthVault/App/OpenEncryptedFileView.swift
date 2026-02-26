//
//  OpenEncryptedFileView.swift
//  HealthVault
//
//  Pick an encrypted .csv.enc or .pdf.enc file, enter password, view decrypted content.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import UIKit

struct OpenEncryptedFileView: View {
    @Environment(\.dismiss) private var dismiss
    let exportService: ZeroKnowledgeExportService?

    @State private var selectedFileURL: URL?
    @State private var password = ""
    @State private var decryptedData: Data?
    @State private var isPDF = false
    @State private var errorMessage: String?
    @State private var isDecrypting = false
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            Group {
                if let data = decryptedData {
                    decryptedContentView(data: data, isPDF: isPDF)
                } else {
                    openFileForm
                }
            }
            .navigationTitle(decryptedData != nil ? "Opened File" : "Open Encrypted File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if decryptedData != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private var openFileForm: some View {
        Form {
            Section {
                if let url = selectedFileURL {
                    Label(url.lastPathComponent, systemImage: "doc.fill")
                }
                Button(selectedFileURL == nil ? "Choose encrypted file" : "Choose another file") {
                    showFileImporter = true
                }
            }

            if selectedFileURL != nil {
                Section("Password") {
                    SecureField("Decryption password", text: $password)
                        .textContentType(.password)
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        decryptAndShow()
                    } label: {
                        HStack {
                            if isDecrypting {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Open with password")
                        }
                    }
                    .disabled(password.isEmpty || isDecrypting)
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.data, .pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                selectedFileURL = url
                password = ""
                errorMessage = nil
                decryptedData = nil
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func decryptAndShow() {
        guard let export = exportService, let url = selectedFileURL else { return }
        isDecrypting = true
        errorMessage = nil
        Task {
            do {
                let encryptedData: Data
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    encryptedData = try Data(contentsOf: url)
                } else {
                    encryptedData = try Data(contentsOf: url)
                }
                let (data, pdf) = try export.openEncryptedData(
                    data: encryptedData,
                    password: password,
                    fileExtension: url.pathExtension
                )
                await MainActor.run {
                    decryptedData = data
                    isPDF = pdf
                    isDecrypting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Decryption failed: \(error.localizedDescription). Check the password."
                    isDecrypting = false
                }
            }
        }
    }

    @ViewBuilder
    private func decryptedContentView(data: Data, isPDF: Bool) -> some View {
        if isPDF {
            PDFKitView(data: data)
        } else {
            csvTextView(data: data)
        }
    }

    private func csvTextView(data: Data) -> some View {
        ScrollView {
            Text(String(data: data, encoding: .utf8) ?? "Could not decode text.")
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        if let doc = PDFDocument(data: data) {
            pdfView.document = doc
        }
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document == nil, let doc = PDFDocument(data: data) {
            pdfView.document = doc
        }
    }
}

#Preview {
    OpenEncryptedFileView(exportService: nil)
}

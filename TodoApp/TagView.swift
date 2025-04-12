import SwiftUI

struct TagView: View {
    let tag: String
    let todoList: TodoList
    @Binding var selectedTag: String?
    @State private var isHovered = false
    @State private var showingRenameSheet = false
    @State private var newTagName = ""
    
    var body: some View {
        HStack {
            Text("#\(tag)")
                .font(.system(size: 14))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isHovered ? Color.blue.opacity(0.2) : Color.blue.opacity(0.1))
                .cornerRadius(8)
                .onHover { hovering in
                    isHovered = hovering
                }
            
            if isHovered {
                Button(action: { showingRenameSheet = true }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .popover(isPresented: $showingRenameSheet) {
            VStack(spacing: 16) {
                Text("Rename Tag")
                    .font(.headline)
                
                TextField("New tag name", text: $newTagName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                HStack {
                    Button("Cancel") {
                        showingRenameSheet = false
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button("Rename") {
                        if !newTagName.isEmpty {
                            todoList.renameTag(from: tag, to: newTagName)
                            if selectedTag == tag {
                                selectedTag = newTagName
                            }
                            showingRenameSheet = false
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(newTagName.isEmpty)
                }
            }
            .padding()
            .frame(width: 200)
        }
        .onTapGesture {
            selectedTag = selectedTag == tag ? nil : tag
        }
    }
}

struct TagCloudView: View {
    let todoList: TodoList
    @Binding var selectedTag: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags & Categories")
                .font(.headline)
                .padding(.bottom, 4)
            
            ScrollView {
                FlowLayout(spacing: 8) {
                    ForEach(Array(todoList.allTags).sorted(), id: \.self) { tag in
                        TagView(tag: tag, todoList: todoList, selectedTag: $selectedTag)
                    }
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.blue.opacity(0.05)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
    }
} 
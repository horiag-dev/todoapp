import SwiftUI

struct NewTodoView: View {
    @ObservedObject var todoList: TodoList
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var priority: Priority = .normal
    @State private var showingTagManagement = false
    @State private var selectedTags: Set<String> = []
    
    var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack {
                Text("New Todo")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            
            // Content
            VStack(alignment: .leading, spacing: 11) {
                // Title input
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("Enter todo title", text: $title)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                // Priority selection
                VStack(alignment: .leading, spacing: 4) {
                    Text("Priority")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack(spacing: 20) {
                        ForEach(Priority.allCases, id: \.self) { p in
                            Button(action: { priority = p }) {
                                HStack {
                                    Image(systemName: p.icon)
                                        .foregroundColor(p.color)
                                    Text(p.rawValue)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    priority == p ?
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(p.color.opacity(0.1)) :
                                    nil
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                // Tags
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tags")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(Array(selectedTags), id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(4)
                                }
                            }
                        }
                        
                        Button(action: { showingTagManagement = true }) {
                            Image(systemName: "tag")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .popover(isPresented: $showingTagManagement) {
                            TagSelectionSheet(
                                todoList: todoList,
                                selectedTags: $selectedTags,
                                isPresented: $showingTagManagement
                            )
                        }
                    }
                }
            }
            .padding()
            
            Spacer()
            
            // Create button
            Button(action: createTodo) {
                Text("Create Todo")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .padding()
            .disabled(title.isEmpty)
        }
        .frame(width: 400, height: 400)
    }
    
    private func createTodo() {
        let todo = Todo(
            title: title,
            isCompleted: false,
            tags: Array(selectedTags),
            priority: priority
        )
        todoList.addTodo(todo)
        dismiss()
    }
}

struct TagSelectionSheet: View {
    @ObservedObject var todoList: TodoList
    @Binding var selectedTags: Set<String>
    @Binding var isPresented: Bool
    @State private var newTag = ""
    
    var availableTags: [String] {
        todoList.allTags.filter { !selectedTags.contains($0) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Tags")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    isPresented = false
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            // Content
            List {
                // Current tags section
                if !selectedTags.isEmpty {
                    Section("Selected Tags") {
                        ForEach(Array(selectedTags), id: \.self) { tag in
                            HStack {
                                Text(tag)
                                Spacer()
                                Button(action: {
                                    selectedTags.remove(tag)
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
                
                // Available tags section
                if !availableTags.isEmpty {
                    Section("Available Tags") {
                        ForEach(availableTags, id: \.self) { tag in
                            Button(action: {
                                selectedTags.insert(tag)
                            }) {
                                HStack {
                                    Text(tag)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                // New tag section
                Section("Create New Tag") {
                    HStack {
                        TextField("Type tag name", text: $newTag)
                            .textFieldStyle(PlainTextFieldStyle())
                        Button(action: {
                            if !newTag.isEmpty {
                                selectedTags.insert(newTag)
                                newTag = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .frame(width: 300, height: 400)
    }
} 
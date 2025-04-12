import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat
    
    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        
        var height: CGFloat = 0
        var width: CGFloat = proposal.width ?? 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxHeight: CGFloat = 0
        
        for size in sizes {
            if currentX + size.width > width {
                // Move to next row
                currentX = 0
                currentY += maxHeight + spacing
                maxHeight = 0
            }
            
            // Position the item
            currentX += size.width + spacing
            maxHeight = max(maxHeight, size.height)
            height = currentY + maxHeight
        }
        
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var maxHeight: CGFloat = 0
        
        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            
            if currentX + size.width > bounds.width {
                // Move to next row
                currentX = bounds.minX
                currentY += maxHeight + spacing
                maxHeight = 0
            }
            
            // Position the item
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )
            
            currentX += size.width + spacing
            maxHeight = max(maxHeight, size.height)
        }
    }
} 
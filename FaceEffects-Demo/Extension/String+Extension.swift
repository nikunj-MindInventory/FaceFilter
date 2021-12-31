//
//  String+Extension.swift
//  FaceEffects-Demo
//
//  Created by Nikunj Prajapati on 29/12/21.
//

import UIKit

extension String {
    
    func convertStringToImage() -> UIImage? {
        
        let nsString = self as NSString
        let font = UIFont.systemFont(ofSize: 80)
        let imageSize = nsString.size(withAttributes: [NSAttributedString.Key.font: font])
        
        UIGraphicsBeginImageContextWithOptions(imageSize, false, 0)
        UIColor.clear.set()
        UIRectFill(CGRect(origin: CGPoint(), size: imageSize))
        nsString.draw(at: CGPoint.zero, withAttributes: [NSAttributedString.Key.font: font])
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image ?? UIImage()
    }
}

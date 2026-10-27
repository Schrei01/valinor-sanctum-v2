import 'package:flutter/material.dart';

class ValinorLogo extends StatelessWidget {
  const ValinorLogo({super.key, this.width = 132, this.height = 108});
  final double width, height;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Logo de Valinor Ludoteca',
    child: SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.all(width <= 48 ? 2 : 8),
            child: Image.asset(
              'assets/branding/valinor-logo.png',
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    ),
  );
}
